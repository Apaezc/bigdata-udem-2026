
-- =====================================================================
-- TALLER 1 - 01_ESTRELLA.SQL
-- CREACION DE LA ESTRUCTURA DEL MODELO ESTRELLA
-- =====================================================================
-- GRANO:
-- Una fila por fecha, zona y empresa.
--
-- TABLAS:
-- DIM_EMPRESA
-- DIM_ZONA
-- DIM_FECHA
-- FACT_VIAJES_DIA
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURSO;

CREATE SCHEMA IF NOT EXISTS CURSO.T1;
USE SCHEMA CURSO.T1;


-- ============================================================
-- 1. DIMENSION EMPRESA
-- Una fila por empresa.
-- Clave primaria: EMPRESA.
-- ============================================================

CREATE OR REPLACE TABLE DIM_EMPRESA (
    EMPRESA VARCHAR(50) NOT NULL,
    CONSTRAINT PK_DIM_EMPRESA PRIMARY KEY (EMPRESA)
);


-- ============================================================
-- 2. DIMENSION ZONA
-- Una fila por nombre de zona.
-- Clave primaria: ZONA.
-- Los nombres repetidos se depuran en 02_carga.sql.
-- ============================================================

CREATE OR REPLACE TABLE DIM_ZONA (
    ZONA VARCHAR(150) NOT NULL,
    BOROUGH VARCHAR(100),
    SERVICE_ZONE VARCHAR(100),
    CONSTRAINT PK_DIM_ZONA PRIMARY KEY (ZONA)
);


-- ============================================================
-- 3. DIMENSION FECHA
-- Una fila por dia del calendario.
-- Clave primaria: FECHA.
-- ============================================================

CREATE OR REPLACE TABLE DIM_FECHA (
    FECHA DATE NOT NULL,
    ANIO NUMBER(4),
    MES NUMBER(2),
    DIA NUMBER(2),
    DIA_SEMANA VARCHAR(10),
    ES_FIN_SEMANA BOOLEAN,
    ES_FESTIVO BOOLEAN,
    LLUVIA_MM FLOAT,
    CONSTRAINT PK_DIM_FECHA PRIMARY KEY (FECHA)
);


-- ============================================================
-- 4. TABLA DE HECHOS
-- Grano: fecha + zona + empresa.
-- Contiene medidas aditivas.
-- ============================================================

CREATE OR REPLACE TABLE FACT_VIAJES_DIA (
    FECHA DATE NOT NULL,
    ZONA VARCHAR(150) NOT NULL,
    EMPRESA VARCHAR(50) NOT NULL,
    VIAJES NUMBER(38,0),
    INGRESO_TOTAL FLOAT,
    PROPINA_TOTAL FLOAT,
    DISTANCIA_TOTAL FLOAT,
    CONSTRAINT PK_FACT_VIAJES_DIA
        PRIMARY KEY (FECHA, ZONA, EMPRESA)
);


-- ============================================================
-- 5. DOCUMENTACION DE LAS CLAVES
-- ============================================================
-- DIM_EMPRESA:
-- EMPRESA identifica de forma unica cada empresa.
--
-- DIM_ZONA:
-- ZONA identifica de forma unica cada zona.
--
-- DIM_FECHA:
-- FECHA identifica de forma unica cada dia.
--
-- FACT_VIAJES_DIA:
-- FECHA + ZONA + EMPRESA identifican cada registro.
--
-- Las relaciones se validan mediante 04_chequeos.sql.
-- =====================================================================
-- FIN DEL ARCHIVO 01_ESTRELLA.SQL
-- =====================================================================
SHOW TABLES IN SCHEMA CURSO.T1;

