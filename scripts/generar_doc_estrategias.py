#!/usr/bin/env python3
"""
Genera el PDF de documentación de estrategias del bot ATLAS EA.
Todo el contenido refleja el código real en src/ (verificado, no de memoria).
"""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, PageBreak, KeepTogether)

OUT = "/Users/croman/Desktop/BOT TRADING/docs/ATLAS_EA_Estrategias.pdf"

# Paleta sobria, legible impresa
AZUL   = colors.HexColor("#12355B")
GRIS   = colors.HexColor("#4A4A4A")
CLARO  = colors.HexColor("#EEF2F6")
VERDE  = colors.HexColor("#1D7A4C")
ROJO   = colors.HexColor("#9E2B25")
AMBAR  = colors.HexColor("#8A6100")
LINEA  = colors.HexColor("#C6CFD8")

styles = getSampleStyleSheet()
S = {
    "titulo": ParagraphStyle("titulo", parent=styles["Title"], fontName="Helvetica-Bold",
                             fontSize=24, textColor=AZUL, spaceAfter=4, leading=28),
    "sub": ParagraphStyle("sub", parent=styles["Normal"], fontName="Helvetica",
                          fontSize=11, textColor=GRIS, alignment=TA_LEFT, spaceAfter=2),
    "h1": ParagraphStyle("h1", parent=styles["Heading1"], fontName="Helvetica-Bold",
                         fontSize=15, textColor=AZUL, spaceBefore=16, spaceAfter=8, leading=18),
    "h2": ParagraphStyle("h2", parent=styles["Heading2"], fontName="Helvetica-Bold",
                         fontSize=12, textColor=AZUL, spaceBefore=11, spaceAfter=5, leading=15),
    "p": ParagraphStyle("p", parent=styles["Normal"], fontName="Helvetica",
                        fontSize=9.7, leading=14.2, spaceAfter=6, textColor=colors.HexColor("#1A1A1A")),
    "celda": ParagraphStyle("celda", parent=styles["Normal"], fontName="Helvetica",
                            fontSize=8.6, leading=11.6),
    "celdaB": ParagraphStyle("celdaB", parent=styles["Normal"], fontName="Helvetica-Bold",
                             fontSize=8.6, leading=11.6),
    "celdaH": ParagraphStyle("celdaH", parent=styles["Normal"], fontName="Helvetica-Bold",
                             fontSize=8.8, leading=11.6, textColor=colors.white),
    "nota": ParagraphStyle("nota", parent=styles["Normal"], fontName="Helvetica",
                           fontSize=9.2, leading=13.4, textColor=colors.HexColor("#333333")),
    "pie": ParagraphStyle("pie", parent=styles["Normal"], fontName="Helvetica",
                          fontSize=7.6, textColor=GRIS),
}

def P(t, s="p"):
    return Paragraph(t, S[s])

def tabla(filas, anchos, header=True):
    data = []
    for i, fila in enumerate(filas):
        estilo = "celdaH" if (header and i == 0) else "celda"
        data.append([Paragraph(str(c), S[estilo]) for c in fila])
    t = Table(data, colWidths=anchos, repeatRows=1 if header else 0)
    cmds = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, LINEA),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    if header:
        cmds += [("BACKGROUND", (0, 0), (-1, 0), AZUL),
                 ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, CLARO])]
    else:
        cmds += [("ROWBACKGROUNDS", (0, 0), (-1, -1), [colors.white, CLARO])]
    t.setStyle(TableStyle(cmds))
    return t

def aviso(texto, color=AMBAR):
    t = Table([[Paragraph(texto, S["nota"])]], colWidths=[16.4 * cm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FBF7EC") if color == AMBAR
         else (colors.HexColor("#FBEDEC") if color == ROJO else colors.HexColor("#EDF6F0"))),
        ("LINEBEFORE", (0, 0), (0, -1), 3, color),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return t

def pie(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINEA)
    canvas.setLineWidth(0.4)
    canvas.line(2.2 * cm, 1.5 * cm, A4[0] - 2.2 * cm, 1.5 * cm)
    canvas.setFont("Helvetica", 7.6)
    canvas.setFillColor(GRIS)
    canvas.drawString(2.2 * cm, 1.05 * cm, "ATLAS EA — Documentación de estrategias · Cuenta demo · Uso personal")
    canvas.drawRightString(A4[0] - 2.2 * cm, 1.05 * cm, f"Página {doc.page}")
    canvas.restoreState()

story = []

# ══════════════ PORTADA ══════════════
story.append(Spacer(1, 6))
story.append(P("ATLAS EA", "titulo"))
story.append(P("Bot de trading automatizado para MetaTrader 5 — documentación de estrategias y operativa", "sub"))
story.append(Spacer(1, 10))
story.append(tabla([
    ["Dato", "Valor"],
    ["Versión", "v2 — estrategias asignadas por instrumento y sesión"],
    ["Instrumentos", "XAUUSD (oro) y EURUSD"],
    ["Plataforma", "MetaTrader 5 · Expert Advisor en MQL5"],
    ["Infraestructura", "Contenedor Docker en servidor propio, operando 24/5"],
    ["Cuenta", "Demo 110545149 (MetaQuotes-Demo) — dinero ficticio, en validación"],
    ["Fecha del documento", "23 de agosto de 2026"],
    ["Código fuente", "github.com/ymk5py-commits/atlas-ea (repositorio privado)"],
], [4.6 * cm, 11.8 * cm]))

story.append(Spacer(1, 14))
story.append(P("Configuración vigente: cada instrumento con lo suyo", "h1"))
story.append(P(
    "La versión 2 abandonó la idea de aplicar las mismas estrategias a todo. Ahora cada instrumento "
    "opera con los motores que le sirven, en la sesión de mercado donde ese instrumento realmente se "
    "mueve. Tras medir cada motor contra tres años y medio de historia, solo Smart Money demostró "
    "ventaja — y solo en el oro. El euro quedó sin operar hasta encontrarle una estrategia que funcione.", "p"))

story.append(Spacer(1, 4))
story.append(tabla([
    ["Instrumento", "Estrategias activas", "Sesión en que opera"],
    ["<b>XAUUSD</b> (oro)", "Smart Money Concepts", "Londres · 08:00 a 17:00 hora de Londres"],
    ["<b>EURUSD</b>", "<font color='#8A6100'>Ninguna — no opera</font>", "Sin estrategia con ventaja demostrada"],
], [3.6 * cm, 7.2 * cm, 5.6 * cm]))

story.append(Spacer(1, 6))
story.append(aviso(
    "<b>El bot ajusta los husos horarios solo.</b> Las horas se configuran en la hora local de cada plaza "
    "financiera y el bot las convierte automáticamente, contemplando el horario de verano de cada país. "
    "No hay que recalcular nada cuando cambia la hora en Europa o Estados Unidos."))

story.append(Spacer(1, 10))
story.append(P("Motores disponibles y su estado", "h1"))
story.append(tabla([
    ["Motor", "Estado actual", "Detalle"],
    ["Smart Money Concepts (SMC)", "<font color='#1D7A4C'><b>Activo</b></font> solo en oro", "Único motor con ventaja medida: +12,2% y la caída más baja"],
    ["Candle Range Theory (CRT)", "<font color='#9E2B25'>Apagado</font>", "Restaba valor en ambos instrumentos (ver resultados)"],
    ["Pullback de tendencia", "<font color='#8A6100'>Disponible, apagado</font>", "Motor validado de la v1, hoy sin instrumentos asignados"],
    ["Ruptura del rango asiático", "<font color='#8A6100'>Disponible, apagado</font>", "Motor de la v1, hoy sin instrumentos asignados"],
    ["Scalping de momentum", "<font color='#9E2B25'>Apagado</font>", "Retirado tras dar −96% en la prueba histórica"],
], [4.6 * cm, 4.6 * cm, 7.2 * cm]))

story.append(PageBreak())

# ══════════════ CRT ══════════════
story.append(P("Motor 1 — Candle Range Theory (ciclo AMD)", "h1"))
story.append(P(
    "La idea de fondo: una vela de temporalidad mayor no es un punto en el gráfico, es un <b>rango</b> con "
    "un ciclo adentro. Ese ciclo tiene tres fases — Acumulación, Manipulación y Distribución — y la "
    "estrategia opera la tercera, que es la que paga.", "p"))
story.append(tabla([
    ["Fase", "Qué ocurre en el mercado", "Qué hace el bot"],
    ["<b>A</b>cumulación", "Una vela de 4 horas define un rango de precios: su máximo y su mínimo",
     "Toma esa vela como referencia. La descarta si es un doji sin recorrido o una vela gigante que ya se movió todo"],
    ["<b>M</b>anipulación", "La vela siguiente perfora uno de los extremos, caza los stops de quienes estaban posicionados, y vuelve adentro del rango",
     "Detecta esa purga. Si perfora los dos extremos, o si la perforación es demasiado profunda, la descarta: eso ya no es barrido, es ruptura real"],
    ["<b>D</b>istribución", "El precio recorre hasta el extremo <b>opuesto</b> del rango",
     "Entra cuando el precio cierra de vuelta dentro del rango con vela de rechazo. El objetivo es el extremo opuesto"],
], [2.6 * cm, 6.6 * cm, 7.2 * cm]))

story.append(Spacer(1, 8))
story.append(P("Filtros que debe pasar la señal", "h2"))
story.append(tabla([
    ["Filtro", "Regla"],
    ["Ubicación en el rango", "Solo vende desde la mitad superior (premium) y solo compra desde la mitad inferior (descuento)"],
    ["Recorrido mínimo", "Si la distancia hasta el extremo opuesto no paga al menos 1,5 veces el riesgo, no opera"],
    ["Confirmación", "Exige vela de rechazo en gráfico de 15 minutos"],
    ["Respeto a la tendencia", "No opera la purga en contra de la tendencia de 1 hora"],
    ["Stop loss", "Al otro lado de la purga, más un colchón de 0,25 × ATR"],
], [4.4 * cm, 12.0 * cm]))

story.append(Spacer(1, 8))
story.append(P(
    "<b>Dos modos de operación:</b> en vivo (entra apenas ocurre la purga, entrada temprana) o confirmado "
    "(espera a que la vela que purgó haya cerrado dentro del rango — más seguro, entrada más tardía).", "p"))

story.append(PageBreak())

# ══════════════ SMC ══════════════
story.append(P("Motor 2 — Smart Money Concepts (solo en oro)", "h1"))
story.append(P(
    "Modelo de entrada institucional. La premisa: los grandes operadores no entran en cualquier precio — "
    "dejan huellas identificables en el gráfico cuando mueven volumen, y esas huellas marcan zonas donde "
    "es probable que vuelvan a actuar.", "p"))
story.append(tabla([
    ["Paso", "Qué busca el bot"],
    ["1. Estructura", "Recorre el gráfico marcando máximos y mínimos relevantes (swings fractales). Cuando el precio cierra más allá del último swing, hay un quiebre: si va en contra del anterior es un <b>cambio de carácter</b> (CHoCH), si lo acompaña es una <b>continuación</b> (BOS)"],
    ["2. Desplazamiento", "Solo cuenta el quiebre si la vela que lo produjo tiene un rango mayor al promedio — movimiento con intención real, no un goteo lateral"],
    ["3. Zona de interés", "Dentro del tramo del impulso busca el <b>Order Block</b> (la última vela contraria antes del movimiento) y el <b>FVG</b> o desequilibrio (hueco entre 3 velas). Si ambos se solapan, refina la zona a la intersección"],
    ["4. Filtros", "La estructura de 1 hora debe acompañar · la zona no debe haber sido ya visitada · el precio debe estar en descuento para comprar o en premium para vender"],
    ["5. Entrada", "Cuando una vela de 15 minutos toca la zona y cierra a favor. El stop va del otro lado de la zona más un colchón de ATR"],
], [3.0 * cm, 13.4 * cm]))

story.append(Spacer(1, 8))
story.append(aviso(
    "Ambos motores nuevos (CRT y Smart Money) tienen <b>parámetros ajustables de selectividad</b>: se "
    "puede exigir barrido de liquidez previo, vela de rechazo, confluencia con el medidor de TradingView "
    "en uno o ambos marcos temporales, y descartar setups cuyo stop resulte demasiado amplio. Cuanto más "
    "estrictos los filtros, menos operaciones pero de mayor calidad."))

story.append(PageBreak())

# ══════════════ ESTRATEGIA 1 ══════════════
story.append(P("Motor 3 — Pullback a favor de la tendencia", "h1"))
story.append(P(
    "<font color='#8A6100'><b>Estado: disponible pero apagado en la configuración vigente.</b></font> "
    "Fue el motor principal de la versión 1 y es el único validado con datos históricos completos "
    "(+22,7% en tres años y medio). Se puede reactivar en cualquier momento asignándole instrumentos.", "p"))
story.append(P(
    "La lógica: cuando un mercado tiene tendencia clara, el precio no sube en línea recta — avanza y "
    "retrocede. Comprar en plena subida es comprar caro; la ventaja está en esperar el retroceso y entrar "
    "cuando el impulso original se reanuda.", "p"))

story.append(P("Condiciones para una compra (la venta es simétrica)", "h2"))
story.append(tabla([
    ["Filtro", "Condición exacta", "Para qué sirve"],
    ["Tendencia mayor",
     "EMA 50 por encima de EMA 200 en gráfico de 1 hora",
     "Confirma que la tendencia de fondo es alcista"],
    ["Confirmación superior",
     "Precio de cierre de 4 horas por encima de su EMA 50",
     "Evita operar contra el marco temporal mayor"],
    ["Zona de retroceso",
     "El precio de 15 min toca la banda EMA 20 ± 0,3 × ATR",
     "Define la zona de valor donde conviene entrar"],
    ["Reanudación del impulso",
     "RSI de 9 períodos cruza el nivel 50 hacia arriba",
     "Marca el momento exacto en que el retroceso termina"],
    ["Rearme del setup",
     "Desde la última señal, el RSI debe haber bajado de 45",
     "Impide entradas repetidas en el mismo movimiento"],
], [3.3 * cm, 6.6 * cm, 6.5 * cm]))

story.append(Spacer(1, 8))
story.append(P("Dónde se coloca el stop loss", "h2"))
story.append(P(
    "Se calculan dos referencias y se toma <b>la más lejana</b>: el mínimo de las últimas 5 velas de 15 "
    "minutos (con margen por spread), o el precio de entrada menos 1,5 × ATR. Elegir la más lejana da "
    "aire a la operación y evita que un movimiento normal del mercado la cierre antes de tiempo.", "p"))

story.append(Spacer(1, 10))

# ══════════════ ESTRATEGIA 2 ══════════════
story.append(P("Motor 4 — Ruptura del rango asiático", "h1"))
story.append(P(
    "<font color='#8A6100'><b>Estado: disponible pero apagado en la configuración vigente.</b></font> "
    "Durante la madrugada (sesión asiática) el oro suele moverse poco y comprimido. Cuando abre Londres "
    "entra volumen de golpe y el precio rompe ese rango estrecho. Esta estrategia marca los límites del "
    "rango nocturno y opera el quiebre confirmado.", "p"))
story.append(tabla([
    ["Elemento", "Definición en el bot"],
    ["Rango de referencia", "Máximo y mínimo entre las 01:00 y las 08:00 hora del servidor"],
    ["Validez del rango", "Solo se opera si el rango mide menos de 1,2 × ATR de 1 hora — si el día ya se movió mucho, no hubo compresión real"],
    ["Ventana de entrada", "De 08:00 a 15:00 hora del servidor"],
    ["Señal de entrada", "Una vela de 15 minutos que <b>cierra</b> fuera del rango (no basta con tocarlo)"],
    ["Stop loss", "Se toma la referencia <b>más cercana</b>: el extremo opuesto del rango, o 1,5 × ATR"],
    ["Límite", "Máximo una ruptura operada por día y por instrumento"],
], [4.2 * cm, 12.2 * cm]))

story.append(Spacer(1, 10))

# ══════════════ FILTRO ══════════════
story.append(P("Filtro de confirmación — réplica del medidor de TradingView", "h1"))
story.append(P(
    "Ninguna señal de las dos estrategias anteriores se ejecuta sola. Antes de abrir, debe pasar por un "
    "filtro que replica dentro del bot el medidor técnico de TradingView: <b>26 indicadores</b> votando "
    "a favor o en contra, cuyo promedio da una calificación desde «venta fuerte» hasta «compra fuerte».", "p"))
story.append(tabla([
    ["Grupo", "Composición", "Cómo vota cada uno"],
    ["Medias móviles<br/>(15 votos)",
     "SMA y EMA de 10, 20, 30, 50, 100 y 200 períodos · Ichimoku · VWMA 20 · Hull MA 9",
     "Voto positivo si el precio está por encima de la media; negativo si está por debajo"],
    ["Osciladores<br/>(11 votos)",
     "RSI · Estocástico · CCI · ADX · Awesome · Momentum · MACD · Stochastic RSI · Williams %R · Bull/Bear Power · Ultimate",
     "Cada uno con su regla propia de sobrecompra, sobreventa y giro"],
], [3.3 * cm, 7.2 * cm, 5.9 * cm]))
story.append(Spacer(1, 6))
story.append(aviso(
    "<b>La regla de confluencia:</b> para una compra, la calificación debe ser «compra» o superior "
    "<b>tanto en 15 minutos como en 1 hora</b>. Si cualquiera de los dos marcos no acompaña, la señal se "
    "descarta y queda registrada en el diario del bot con el motivo. Lo mismo, invertido, para ventas."))

story.append(Spacer(1, 14))

# ══════════════ ESTRATEGIA 3 ══════════════
story.append(P("Motor 5 — Scalping de momentum (retirado)", "h1"))
story.append(P(
    "<font color='#9E2B25'><b>Estado: apagado tras la prueba histórica.</b></font> "
    "Motor de operaciones rápidas en gráfico de 1 minuto sobre el oro, construido replicando el estilo de "
    "operación manual del usuario: entradas a favor de un impulso fuerte, con salida en minutos.", "p"))
story.append(tabla([
    ["Elemento", "Definición en el bot"],
    ["Señal de compra", "EMA 9 sobre EMA 21 · precio de cierre sobre la EMA 9 · RSI de 7 períodos en 60 o más · el cierre supera el máximo de las 3 velas previas"],
    ["Señal de venta", "Condiciones simétricas: EMA 9 bajo EMA 21, RSI de 7 en 40 o menos, cierre bajo el mínimo de las 3 velas previas"],
    ["Stop loss", "1,2 × ATR de 1 minuto"],
    ["Objetivo", "1 R (misma distancia que el riesgo)"],
    ["Protección", "Break-even a la mitad del camino (0,5 R)"],
    ["Salida por tiempo", "Cierre automático a los 20 minutos si no definió"],
    ["Límites", "Máximo 15 por día · 3 minutos de espera entre operaciones"],
], [4.2 * cm, 12.2 * cm]))
story.append(Spacer(1, 8))
story.append(aviso(
    "<b>Advertencia sobre este motor.</b> A diferencia de los dos anteriores, el scalping fue construido "
    "después de la validación original y <b>nunca fue probado contra datos históricos largos</b> hasta el "
    "20 de agosto de 2026. En esa prueba, sobre 3 años y medio de historia real, la configuración con "
    "scalping activo llevó una cuenta de 500 USD a 18 USD (una pérdida del 96%), con una caída máxima del "
    "82%. El resultado se repitió casi idéntico en dos configuraciones horarias distintas, lo que descarta "
    "que se trate de casualidad. El resultado positivo observado en los primeros días de operación en vivo "
    "(+11%) corresponde a una muestra demasiado corta para ser concluyente. "
    "<b>En la versión 2 el motor quedó desactivado</b> y su lugar lo ocupan Candle Range Theory y Smart Money Concepts.", ROJO))

story.append(Spacer(1, 12))

# ══════════════ GESTIÓN ══════════════
story.append(P("Cómo se gestiona cada operación abierta", "h1"))
story.append(P(
    "Abrir bien es la mitad del trabajo; la otra mitad es administrar la posición. El bot nunca deja una "
    "operación sin protección y ajusta el riesgo a medida que la operación avanza a favor.", "p"))
story.append(tabla([
    ["Momento", "Acción automática"],
    ["Al abrir", "Toda orden lleva stop loss desde el primer segundo. El tamaño del lote se calcula para que ese stop represente exactamente el riesgo configurado"],
    ["Al llegar a +1 R", "El stop se mueve al punto de entrada (break-even): a partir de ahí la operación ya no puede terminar en pérdida"],
    ["Al llegar a +1 R (lote grande)", "Se cierra la mitad de la posición para asegurar ganancia; el resto queda corriendo"],
    ["Mientras avanza", "Trailing stop que sigue al precio a 2 × ATR de distancia — deja correr las ganancias sin devolver todo en un retroceso"],
    ["Objetivo fijo", "2 R cuando el lote es indivisible (cuentas chicas donde no se puede cerrar la mitad)"],
    ["Viernes", "Sin entradas nuevas en las últimas 2 horas de sesión y cierre total 1 hora antes del fin — evita el riesgo del fin de semana"],
], [4.6 * cm, 11.8 * cm]))

story.append(PageBreak())

# ══════════════ RIESGO ══════════════
story.append(P("Sistema de protección del capital", "h1"))
story.append(P(
    "Los frenos están diseñados en capas: cada uno actúa en una escala distinta, desde la operación "
    "individual hasta la cuenta completa.", "p"))
story.append(tabla([
    ["Freno", "Valor actual", "Qué evita"],
    ["Stop loss obligatorio", "En cada orden, sin excepción", "Que una operación quede expuesta sin límite"],
    ["Riesgo por operación", "1,5% del capital", "Que un solo trade pueda hacer daño relevante"],
    ["Cálculo de lote blindado", "Triple verificación, se usa la más conservadora", "Que un dato erróneo del broker infle el tamaño de la posición"],
    ["Riesgo total simultáneo", "Máximo 3% del capital", "Que varias posiciones juntas superen el límite"],
    ["Límite de pérdida diaria", "5% — el bot deja de operar hasta el día siguiente", "Que un mal día se convierta en catástrofe"],
    ["Anti-sobreoperación", "4 operaciones por día e instrumento · 2 posiciones simultáneas", "Que el bot opere de más en mercados difíciles"],
    ["Freno de emergencia", "Caída del 30% desde el máximo: cierra todo y se apaga", "La pérdida total de la cuenta. Solo se reactiva manualmente"],
    ["Protección de cuenta chica", "Si el lote mínimo supera el riesgo permitido, no opera", "Forzar operaciones desproporcionadas al capital"],
], [4.0 * cm, 5.0 * cm, 7.4 * cm]))

story.append(Spacer(1, 10))
story.append(P("Cuándo el bot NO opera", "h1"))
story.append(tabla([
    ["Filtro", "Regla"],
    ["Horario", "Cada instrumento solo en su sesión: el oro en Londres (08:00–17:00 hora de Londres), el euro en Nueva York (08:00–13:00 hora de Nueva York), de lunes a viernes"],
    ["Noticias de alto impacto", "Se detiene 30 minutos antes y después de eventos como inflación, empleo, decisiones de tasas y PIB, usando el calendario económico de MetaTrader"],
    ["Spread alto", "No opera si el costo de entrada supera el límite configurado por instrumento"],
    ["Mercado lateral", "Si no hay tendencia ni compresión, ninguna estrategia se activa"],
    ["Sin confirmación técnica", "Si el medidor de 26 indicadores no acompaña en ambos marcos temporales"],
], [4.6 * cm, 11.8 * cm]))

story.append(Spacer(1, 10))
story.append(P("Resultados de las pruebas históricas", "h1"))
story.append(P(
    "Todas las pruebas se corrieron sobre datos reales de precio entre enero de 2023 y julio de 2026, "
    "partiendo de 500 USD, con las mismas reglas de gestión y riesgo.", "p"))
story.append(tabla([
    ["Configuración probada", "Resultado final", "Operaciones", "Caída máxima"],
    ["<b>Pullback + Ruptura</b>, sesión Londres/NY<br/><font size=7.5 color=\'#1D7A4C\'>Motor validado de la v1</font>",
     "<b>613,47 USD</b><br/><font size=7.5>+22,7%</font>", "917", "23,9%"],
    ["Pullback + Ruptura, horario ampliado 24h<br/><font size=7.5 color=\'#9E2B25\'>Descartado tras la prueba</font>",
     "296,41 USD<br/><font size=7.5>−40,7%</font>", "1.321", "47,1%"],
    ["Con scalping activo, sesión Londres/NY<br/><font size=7.5 color=\'#9E2B25\'>Motor retirado</font>",
     "18,04 USD<br/><font size=7.5>−96,4%</font>", "1.042", "81,9%"],
    ["Con scalping activo, horario ampliado 24h<br/><font size=7.5 color=\'#9E2B25\'>Motor retirado</font>",
     "18,41 USD<br/><font size=7.5>−96,3%</font>", "1.120", "81,9%"],
], [7.2 * cm, 3.4 * cm, 2.6 * cm, 3.2 * cm]))

story.append(Spacer(1, 8))
story.append(Spacer(1, 8))
story.append(aviso(
    "<b>Expectativa realista.</b> El único motor validado rinde aproximadamente <b>6% anual</b> en la "
    "prueba histórica, con rachas negativas de hasta 24%. No existe ningún sistema de trading que genere "
    "rentabilidades altas de forma constante y sin riesgo: los resultados pasados no garantizan resultados "
    "futuros, y toda operación apalancada puede generar pérdidas. El bot opera actualmente en cuenta demo "
    "con dinero ficticio, en fase de validación.", AMBAR))

doc = SimpleDocTemplate(
    OUT, pagesize=A4,
    leftMargin=2.2 * cm, rightMargin=2.2 * cm,
    topMargin=1.8 * cm, bottomMargin=2.0 * cm,
    title="ATLAS EA — Documentación de estrategias",
    author="ATLAS EA", subject="Estrategias y operativa del bot de trading",
)
doc.build(story, onFirstPage=pie, onLaterPages=pie)
print("PDF generado:", OUT)
