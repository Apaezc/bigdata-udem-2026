"""Archivos del lake: el borrado por lotes y las primitivas sobre file:// (sin Spark ni red)."""

from __future__ import annotations

import pytest

from pipeline.herramientas import archivos


class S3Falso:
    def __init__(self, errores=None):
        self.llamadas: list[int] = []
        self.errores = errores or []

    def delete_objects(self, Bucket, Delete):  # noqa: N803 (así se llama en boto3)
        self.llamadas.append(len(Delete["Objects"]))
        return {"Errors": self.errores}


def test_borrar_claves_borra_de_mil_en_mil():
    s3 = S3Falso()
    claves = [f"dev/gold/x/{i}" for i in range(2500)]
    assert archivos.borrar_claves(s3, "bucket", claves) == 2500
    assert s3.llamadas == [1000, 1000, 500]


def test_borrar_claves_se_detiene_si_s3_reporta_un_error():
    s3 = S3Falso(errores=[{"Key": "dev/a", "Code": "AccessDenied", "Message": "no"}])
    with pytest.raises(RuntimeError, match="no pudo borrar 1 objeto"):
        archivos.borrar_claves(s3, "bucket", ["dev/a"])


def test_borrar_carpeta_local_borra_todo_lo_de_adentro(tmp_path):
    carpeta = tmp_path / "mes=2024-01"
    (carpeta / "lote=1").mkdir(parents=True)
    (carpeta / "lote=1" / "parte.parquet").write_text("x")
    archivos.borrar_carpeta(f"file://{carpeta}")
    assert not carpeta.exists()


def test_el_lote_completo_se_marca_al_final(tmp_path):
    carpeta = f"file://{tmp_path}/lote=L1"
    assert not archivos.existe(archivos.unir(carpeta, archivos.MARCA_LOTE_COMPLETO))
    archivos.marcar_lote_completo(carpeta)
    assert archivos.existe(archivos.unir(carpeta, archivos.MARCA_LOTE_COMPLETO))
    assert archivos.listar_subcarpetas(f"file://{tmp_path}") == ["lote=L1"]
