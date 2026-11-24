"""La VM de prod debe pasar LAKE_BUCKET a los contenedores: sin él, correr_bronze falla en prod."""

from pathlib import Path

AIRFLOW = Path(__file__).resolve().parents[1]


def test_el_refresco_de_la_vm_escribe_lake_env():
    texto = (AIRFLOW / "vm" / "airflow-refresh.sh").read_text(encoding="utf-8")
    assert 'LAKE_BUCKET=$LAKE" > "$AIRFLOW_HOME/lake.env"' in texto


def test_el_compose_carga_lake_env_en_los_contenedores():
    texto = (AIRFLOW / "docker-compose.yaml").read_text(encoding="utf-8")
    assert "path: ./lake.env" in texto
