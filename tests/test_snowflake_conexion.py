"""conexion_snowflake_json (scripts/lib.sh): JSON de la conexión snowflake_default de Airflow.

Solo local: valores falsos y una llave generada con openssl; no toca AWS ni Snowflake.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

LIB = Path(__file__).resolve().parents[1] / "scripts" / "lib.sh"
ARGS = ["AIRFLOW_SVC", "org-cuenta", "BIGDATA_WH", "BIGDATA", "BIGDATA_DEV"]

pytestmark = pytest.mark.skipif(
    shutil.which("jq") is None or shutil.which("openssl") is None, reason="requiere jq y openssl"
)


def _llamar(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-c", 'source "$1"; shift; conexion_snowflake_json "$@"', "_", str(LIB), *args],
        capture_output=True,
        text=True,
    )


@pytest.fixture()
def llave(tmp_path) -> Path:
    pem = tmp_path / "airflow_svc_rsa_key.p8"
    genkey = subprocess.run(["openssl", "genrsa", "2048"], capture_output=True, check=True)
    pem.write_bytes(
        subprocess.run(
            ["openssl", "pkcs8", "-topk8", "-inform", "PEM", "-nocrypt"],
            input=genkey.stdout,
            capture_output=True,
            check=True,
        ).stdout
    )
    return pem


def test_json_de_conexion_para_el_provider_snowflake(llave):
    r = _llamar(*ARGS, str(llave))
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert d["conn_type"] == "snowflake"
    assert d["login"] == "AIRFLOW_SVC"
    assert "password" not in d
    assert {k: v for k, v in d["extra"].items() if k != "private_key_content"} == {
        "account": "org-cuenta",
        "warehouse": "BIGDATA_WH",
        "database": "BIGDATA",
        "role": "BIGDATA_DEV",
    }
    pem = d["extra"]["private_key_content"]
    # Tal cual: el provider hace load_pem_private_key(content.encode()).
    assert pem == llave.read_text()
    assert pem.startswith("-----BEGIN PRIVATE KEY-----\n")
    assert pem.rstrip().endswith("-----END PRIVATE KEY-----")


def test_es_compatible_con_user_data_y_airflow_local(llave):
    """Una línea, con conn_type, sin comilla simple (la VM la mete entre comillas simples)."""
    r = _llamar(*ARGS, str(llave))
    salida = r.stdout.rstrip("\n")
    assert "\n" not in salida
    assert "'" not in salida
    # Mismas comprobaciones que airflow-refresh.sh (user_data.sh.tftpl) y airflow-local.sh.
    d = json.loads(salida)
    assert isinstance(d, dict) and "conn_type" in d
    jq = subprocess.run(["jq", "-e", ".conn_type"], input=salida, capture_output=True, text=True)
    assert jq.returncode == 0


def test_falla_sin_llave_o_con_argumentos_de_menos(tmp_path):
    assert _llamar(*ARGS, str(tmp_path / "no-existe.p8")).returncode != 0
    assert _llamar(*ARGS).returncode != 0


def test_no_imprime_la_llave_en_los_errores(llave):
    r = _llamar("solo", "dos", str(llave))
    assert r.returncode != 0
    assert "PRIVATE KEY" not in r.stdout + r.stderr
