from __future__ import annotations

from pyspark.sql import functions as F

from pipeline.silver import clima_diario, enriquecer, limpiar_taxi_zones, limpiar_viajes

MESES = ["2024-01"]

COLS_ENTRADA = (
    "hvfhs_license_num string, pickup_datetime string, dropoff_datetime string, "
    "PULocationID int, DOLocationID int, trip_miles double, trip_time int, "
    "base_passenger_fare double, tolls double, bcf double, sales_tax double, "
    "congestion_surcharge double, airport_fee double, tips double, driver_pay double"
)


def _viaje(pickup, segundos=1200, pu=43, distancia=3.0, tarifa=12.0, licencia="HV0003"):
    return (
        licencia,
        pickup,
        None,
        pu,
        79,
        distancia,
        segundos,
        tarifa,
        0.0,
        0.3,
        1.0,
        2.75,
        None,
        2.0,
        9.0,
    )


def test_limpiar_viajes_filtra_cada_tipo_de_outlier(spark):
    buena = _viaje("2024-01-10 10:00:00")
    malas = [
        _viaje("2024-01-10 10:00:00", distancia=0.0),
        _viaje("2024-01-10 10:00:00", distancia=100.0),
        _viaje("2024-01-10 10:00:00", tarifa=0.0),
        _viaje("2024-01-10 10:00:00", segundos=0),  # 0 min
        _viaje("2024-01-10 10:00:00", segundos=181 * 60),  # 181 min
        _viaje("2024-01-10 10:00:00", pu=None),
        _viaje("2023-12-31 23:50:00"),  # antes del rango
        _viaje("2024-02-01 00:05:00"),  # después del rango
    ]
    df = spark.createDataFrame([buena, *malas], COLS_ENTRADA)

    limpio = limpiar_viajes(df, MESES).collect()

    assert len(limpio) == 1
    fila = limpio[0]
    assert str(fila["pickup_date"]) == "2024-01-10"
    assert fila["duracion_min"] == 20.0
    assert fila["empresa"] == "Uber"
    # total pagado = tarifa + peajes + bcf + impuesto + congestión + aeropuerto (nulo=0) + propina
    assert fila["total_pagado"] == 12.0 + 0.0 + 0.3 + 1.0 + 2.75 + 0.0 + 2.0


def test_limpiar_viajes_rango_de_varios_meses(spark):
    df = spark.createDataFrame(
        [
            _viaje("2024-01-31 23:00:00"),
            _viaje("2024-02-15 10:00:00"),
            _viaje("2024-03-01 00:10:00"),
        ],
        COLS_ENTRADA,
    )
    assert limpiar_viajes(df, ["2024-01", "2024-02"]).count() == 2
    assert limpiar_viajes(df).count() == 3


def test_empresa_desde_licencia(spark):
    df = spark.createDataFrame(
        [
            _viaje("2024-01-10 10:00:00", licencia="HV0003"),
            _viaje("2024-01-10 10:00:00", licencia="HV0005"),
            _viaje("2024-01-10 10:00:00", licencia="HV0099"),
        ],
        COLS_ENTRADA,
    )
    empresas = sorted(r["empresa"] for r in limpiar_viajes(df, MESES).collect())
    assert empresas == ["Lyft", "Otra HV0099", "Uber"]


def test_limpiar_viajes_muestra_csv(muestra_viajes):
    limpio = limpiar_viajes(muestra_viajes, MESES)

    # 90 viajes válidos en la muestra; los 10 outliers se descartan
    assert limpio.count() == 90
    rangos = limpio.agg(
        F.min("distancia_mi").alias("d_min"),
        F.max("distancia_mi").alias("d_max"),
        F.min("duracion_min").alias("u_min"),
        F.max("duracion_min").alias("u_max"),
        F.min("tarifa_base").alias("f_min"),
        F.min("pickup_date").alias("p_min"),
        F.max("pickup_date").alias("p_max"),
    ).first()
    assert 0 < rangos["d_min"] and rangos["d_max"] < 100
    assert 1 <= rangos["u_min"] and rangos["u_max"] <= 180
    assert rangos["f_min"] > 0
    assert str(rangos["p_min"]) >= "2024-01-01" and str(rangos["p_max"]) <= "2024-01-31"
    assert {r["empresa"] for r in limpio.select("empresa").distinct().collect()} == {"Uber", "Lyft"}


def test_clima_diario_renombra_y_tipa_el_clima_de_bronze(muestra_clima):
    clima = clima_diario(muestra_clima)

    assert clima.columns == ["fecha", "lluvia_mm", "temp_media_c"]
    assert clima.count() == 31
    assert dict(clima.dtypes)["fecha"] == "date"


def test_enriquecer_conserva_filas_y_asigna_zona_y_lluvia(
    muestra_viajes, muestra_zonas, muestra_clima
):
    trips = limpiar_viajes(muestra_viajes, MESES)
    clima = clima_diario(muestra_clima)

    silver = enriquecer(trips, muestra_zonas, clima)

    assert silver.count() == trips.count()  # left joins: no se pierden viajes
    fila_jfk = silver.where("pu_location_id = 132").select("zona", "borough").first()
    assert fila_jfk["zona"] == "JFK Airport"
    assert fila_jfk["borough"] == "Queens"

    fuera = silver.where("pu_location_id = 250").select("zona").first()
    assert fuera["zona"] == "Zona 250"

    # la lluvia de cada viaje es la del día de recogida
    esperada = clima.withColumnRenamed("fecha", "pickup_date")
    cruce = (
        silver.select("pickup_date", "lluvia_mm")
        .distinct()
        .join(
            esperada.select("pickup_date", F.col("lluvia_mm").alias("lluvia_esperada")),
            "pickup_date",
        )
    )
    assert cruce.where("lluvia_mm <> lluvia_esperada OR lluvia_mm IS NULL").count() == 0


# --- metadatos de bronze: se conservan si existen y no estorban si no --------------------------

METADATOS = ["_hash_fila", "_id_lote", "_fecha_ingesta"]


def test_limpiar_viajes_conserva_los_metadatos_cuando_existen(spark):
    df = spark.createDataFrame([_viaje("2024-01-10 10:00:00")], COLS_ENTRADA)
    con_metadatos = (
        df.withColumn("_hash_fila", F.lit("h1"))
        .withColumn("_id_lote", F.lit("lote1"))
        .withColumn("_fecha_ingesta", F.current_timestamp())
        .withColumn("_fuente", F.lit("url"))
    )

    limpio = limpiar_viajes(con_metadatos, MESES)

    assert limpio.columns[-len(METADATOS) - 1 :] == [*METADATOS, "pickup_date"]
    assert "_fuente" not in limpio.columns  # solo pasan los tres que se usan aguas abajo
    assert limpio.first()["_hash_fila"] == "h1"


def test_limpiar_viajes_no_falla_si_la_entrada_no_trae_metadatos(spark):
    df = spark.createDataFrame([_viaje("2024-01-10 10:00:00")], COLS_ENTRADA)
    limpio = limpiar_viajes(df, MESES)
    assert not set(METADATOS) & set(limpio.columns)
    assert limpio.count() == 1


def test_clima_diario_conserva_los_metadatos_cuando_existen(muestra_clima):
    con_metadatos = muestra_clima.withColumn("_hash_fila", F.lit("h")).withColumn(
        "_id_lote", F.lit("lote1")
    )
    clima = clima_diario(con_metadatos)
    assert clima.columns == ["fecha", "lluvia_mm", "temp_media_c", "_hash_fila", "_id_lote"]


def test_limpiar_taxi_zones_castea_el_id_y_conserva_las_columnas(muestra_zonas):
    zonas = limpiar_taxi_zones(muestra_zonas)
    assert zonas.columns == ["LocationID", "Borough", "Zone", "service_zone"]
    assert dict(zonas.dtypes)["LocationID"] == "int"
    assert zonas.count() == muestra_zonas.count()


def test_limpiar_taxi_zones_conserva_los_metadatos_cuando_existen(muestra_zonas):
    con_metadatos = muestra_zonas.withColumn("_hash_fila", F.lit("h")).withColumn(
        "_fecha_ingesta", F.current_timestamp()
    )
    zonas = limpiar_taxi_zones(con_metadatos)
    assert zonas.columns == [
        "LocationID",
        "Borough",
        "Zone",
        "service_zone",
        "_hash_fila",
        "_fecha_ingesta",
    ]


def test_enriquecer_deja_pasar_los_metadatos_de_los_viajes(spark, muestra_zonas, muestra_clima):
    viajes = limpiar_viajes(
        spark.createDataFrame([_viaje("2024-01-10 10:00:00")], COLS_ENTRADA).withColumn(
            "_hash_fila", F.lit("h1")
        ),
        MESES,
    )
    silver = enriquecer(viajes, limpiar_taxi_zones(muestra_zonas), clima_diario(muestra_clima))
    assert silver.first()["_hash_fila"] == "h1"
