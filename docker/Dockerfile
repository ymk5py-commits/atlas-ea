# ATLAS EA — MetaTrader 5 headless en contenedor aislado
# Corre en cualquier servidor Linux con Docker, sin tocar el sistema anfitrión.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    WINEPREFIX=/mt5/wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    TZ=UTC

# Wine + Xvfb (pantalla virtual) + utilidades
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine wine64 wine32:i386 xvfb xauth \
        wget ca-certificates cabextract winbind \
        fonts-liberation procps psmisc tzdata && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /mt5

# Instalación desatendida de MetaTrader 5 bajo Wine
RUN wineboot --init >/dev/null 2>&1 || true; sleep 5; \
    wget -q -O /tmp/mt5setup.exe \
      "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" && \
    xvfb-run -a wine /tmp/mt5setup.exe /auto >/dev/null 2>&1 || true; \
    sleep 45; \
    rm -f /tmp/mt5setup.exe; \
    test -f "${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe" || \
      (echo "ERROR: MT5 no se instalo" && exit 1)

# Ruta sin espacios: el compilador CLI de MetaEditor falla con espacios,
# y COPY tampoco admite rutas con espacios dentro de una variable.
RUN ln -sfn "${WINEPREFIX}/drive_c/Program Files/MetaTrader 5" /mt5/term && \
    ln -sfn "${WINEPREFIX}/drive_c/Program Files/MetaTrader 5" "${WINEPREFIX}/drive_c/mt5"

# Primer arranque: MetaTrader crea aquí la librería estándar MQL5 (Trade.mqh, etc.),
# que no viene desempaquetada con el instalador. Sin esto, el EA no compila.
RUN (xvfb-run -a wine 'C:\mt5\terminal64.exe' /portable >/dev/null 2>&1 &) ; \
    for i in $(seq 1 24); do \
      sleep 5; \
      [ -f /mt5/term/MQL5/Include/Trade/Trade.mqh ] && break; \
    done; \
    pkill -f terminal64.exe || true; sleep 3; \
    test -f /mt5/term/MQL5/Include/Trade/Trade.mqh || \
      (echo "ERROR: MT5 no desempaqueto la libreria estandar" && exit 1); \
    echo "Libreria estandar MQL5 lista"; \
    mkdir -p /mt5/term/MQL5/Experts/Atlas

# Código del bot
COPY src/ /mt5/term/MQL5/Experts/Atlas/

# Compilación del EA dentro de la imagen (falla el build si no compila)
RUN xvfb-run -a wine 'C:\mt5\metaeditor64.exe' \
        '/compile:C:\mt5\MQL5\Experts\Atlas\Atlas_EA.mq5' \
        '/log:C:\mt5\compile.log' >/dev/null 2>&1 || true; \
    sleep 5; \
    iconv -f UTF-16LE -t UTF-8 /mt5/term/compile.log 2>/dev/null | grep -aE "error|Result:" | head -20 || true; \
    test -f /mt5/term/MQL5/Experts/Atlas/Atlas_EA.ex5 || \
      (echo "ERROR: el EA no compilo" && exit 1)

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
