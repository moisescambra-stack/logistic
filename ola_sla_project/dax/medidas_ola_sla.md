# Medidas DAX — Dashboard OLA & ANS/SLA
# Stack: Power BI · DAX · Star Schema
# Autor: Moisés Cambra

# ═══════════════════════════════════════════════════════
# BLOQUE 1 — KPIs BÁSICOS DE INCIDENCIAS
# ═══════════════════════════════════════════════════════

Total Incidencias =
COUNTROWS(fact_incidencias)

Incidencias Cerradas =
CALCULATE(
    COUNTROWS(fact_incidencias),
    fact_incidencias[estado] = "Cerrada"
)

Incidencias Abiertas =
CALCULATE(
    COUNTROWS(fact_incidencias),
    fact_incidencias[estado] = "Abierta"
)

# ═══════════════════════════════════════════════════════
# BLOQUE 2 — MTTR (Mean Time To Resolve)
# ═══════════════════════════════════════════════════════

MTTR Minutos =
CALCULATE(
    AVERAGEX(
        FILTER(fact_incidencias, fact_incidencias[estado] = "Cerrada"),
        fact_incidencias[tiempo_resolucion_min]
    )
)

MTTR Horas =
DIVIDE([MTTR Minutos], 60, 0)

MTTR Formato =
VAR _horas = INT([MTTR Horas])
VAR _minutos = INT(([MTTR Horas] - _horas) * 60)
RETURN _horas & "h " & _minutos & "m"

# ═══════════════════════════════════════════════════════
# BLOQUE 3 — MTTR (Mean Time To Respond)
# ═══════════════════════════════════════════════════════

MTTRESPONSE Minutos =
AVERAGEX(
    fact_incidencias,
    fact_incidencias[tiempo_respuesta_min]
)

# ═══════════════════════════════════════════════════════
# BLOQUE 4 — CUMPLIMIENTO ANS/SLA
# ═══════════════════════════════════════════════════════

# Verifica si el tiempo de respuesta cumple el SLA según prioridad
Cumple SLA Respuesta =
COUNTX(
    FILTER(
        fact_incidencias,
        VAR _p = fact_incidencias[prioridad]
        VAR _tr = fact_incidencias[tiempo_respuesta_min]
        VAR _objetivo =
            SWITCH(
                _p,
                "P1", RELATED(dim_contratos[sla_respuesta_p1_min]),
                "P2", RELATED(dim_contratos[sla_respuesta_p2_min]),
                "P3", RELATED(dim_contratos[sla_respuesta_p3_min]),
                999
            )
        RETURN _tr <= _objetivo
    ),
    fact_incidencias[id_incidencia]
)

Cumplimiento SLA Respuesta % =
DIVIDE(
    [Cumple SLA Respuesta],
    [Total Incidencias],
    0
)

# Cumplimiento de resolución (solo incidencias cerradas)
Cumple SLA Resolucion =
COUNTX(
    FILTER(
        fact_incidencias,
        fact_incidencias[estado] = "Cerrada" &&
        VAR _p  = fact_incidencias[prioridad]
        VAR _tr = fact_incidencias[tiempo_resolucion_min]
        VAR _objetivo =
            SWITCH(
                _p,
                "P1", RELATED(dim_contratos[sla_resolucion_p1_min]),
                "P2", RELATED(dim_contratos[sla_resolucion_p2_min]),
                "P3", RELATED(dim_contratos[sla_resolucion_p3_min]),
                9999
            )
        RETURN _tr <= _objetivo
    ),
    fact_incidencias[id_incidencia]
)

Cumplimiento SLA Resolucion % =
DIVIDE(
    [Cumple SLA Resolucion],
    [Incidencias Cerradas],
    0
)

# SLA Global combinado (respuesta + resolución ponderado)
SLA Global % =
([Cumplimiento SLA Respuesta %] * 0.4) + ([Cumplimiento SLA Resolucion %] * 0.6)

# ═══════════════════════════════════════════════════════
# BLOQUE 5 — SEMÁFOROS EWI (Early Warning Indicators)
# ═══════════════════════════════════════════════════════

Semaforo SLA =
VAR _sla = [SLA Global %]
RETURN
    IF(_sla >= 0.95, "🟢 Cumple",
    IF(_sla >= 0.90, "🟡 Atención",
    "🔴 Incumple"))

EWI SLA Alerta =
VAR _sla = [SLA Global %]
VAR _objetivo = 0.95
VAR _brecha = _objetivo - _sla
RETURN
    IF(_brecha <= 0, "En objetivo",
    IF(_brecha <= 0.03, "⚠️ Riesgo leve — brecha " & FORMAT(_brecha, "0.0%"),
    "🚨 Incumplimiento — brecha " & FORMAT(_brecha, "0.0%")))

Semaforo Incidencias P1 =
VAR _p1 = CALCULATE([Total Incidencias], fact_incidencias[prioridad] = "P1")
RETURN
    IF(_p1 = 0, "🟢 Sin P1",
    IF(_p1 <= 3, "🟡 " & _p1 & " P1 activas",
    "🔴 " & _p1 & " P1 — revisar"))

# ═══════════════════════════════════════════════════════
# BLOQUE 6 — OLA (Acuerdos Internos por Equipo)
# ═══════════════════════════════════════════════════════

# First Time Fix Rate por equipo
FTFR % =
DIVIDE(
    CALCULATE(
        COUNTROWS(fact_incidencias),
        fact_incidencias[resuelto_primera_vez] = 1
    ),
    [Incidencias Cerradas],
    0
)

Semaforo FTFR =
VAR _ftfr = [FTFR %]
RETURN
    IF(_ftfr >= 0.90, "🟢 " & FORMAT(_ftfr, "0.0%"),
    IF(_ftfr >= 0.80, "🟡 " & FORMAT(_ftfr, "0.0%"),
    "🔴 " & FORMAT(_ftfr, "0.0%")))

Tasa Reapertura % =
DIVIDE(
    CALCULATE(
        COUNTROWS(fact_incidencias),
        fact_incidencias[reabierta] = 1
    ),
    [Incidencias Cerradas],
    0
)

EWI Reapertura =
IF([Tasa Reapertura %] > 0.10,
    "🔴 Tasa reapertura alta: " & FORMAT([Tasa Reapertura %], "0.0%"),
    "🟢 Tasa reapertura OK: " & FORMAT([Tasa Reapertura %], "0.0%"))

# ═══════════════════════════════════════════════════════
# BLOQUE 7 — ANÁLISIS DE TENDENCIA (Rolling 7 días)
# ═══════════════════════════════════════════════════════

Incidencias Rolling 7D =
CALCULATE(
    [Total Incidencias],
    DATESINPERIOD(
        dim_calendario[fecha],
        LASTDATE(dim_calendario[fecha]),
        -7,
        DAY
    )
)

MTTR Rolling 7D =
CALCULATE(
    [MTTR Minutos],
    DATESINPERIOD(
        dim_calendario[fecha],
        LASTDATE(dim_calendario[fecha]),
        -7,
        DAY
    )
)

# ═══════════════════════════════════════════════════════
# BLOQUE 8 — KPIs POR PRIORIDAD
# ═══════════════════════════════════════════════════════

Incidencias P1 =
CALCULATE([Total Incidencias], fact_incidencias[prioridad] = "P1")

Incidencias P2 =
CALCULATE([Total Incidencias], fact_incidencias[prioridad] = "P2")

Incidencias P3 =
CALCULATE([Total Incidencias], fact_incidencias[prioridad] = "P3")

Incidencias P4 =
CALCULATE([Total Incidencias], fact_incidencias[prioridad] = "P4")

MTTR P1 Minutos =
CALCULATE([MTTR Minutos], fact_incidencias[prioridad] = "P1")

MTTR P2 Minutos =
CALCULATE([MTTR Minutos], fact_incidencias[prioridad] = "P2")

# ═══════════════════════════════════════════════════════
# BLOQUE 9 — TÍTULOS DINÁMICOS
# ═══════════════════════════════════════════════════════

Titulo Dinamico Contrato =
VAR _contrato = SELECTEDVALUE(dim_contratos[cliente], "Todos los contratos")
RETURN "Cumplimiento SLA — " & _contrato

Titulo Dinamico Equipo =
VAR _equipo = SELECTEDVALUE(dim_equipos[nombre_equipo], "Todos los equipos")
RETURN "OLA — " & _equipo

Subtitulo Periodo =
VAR _min = FORMAT(MIN(dim_calendario[fecha]), "DD/MM/YYYY")
VAR _max = FORMAT(MAX(dim_calendario[fecha]), "DD/MM/YYYY")
RETURN "Período: " & _min & " – " & _max
