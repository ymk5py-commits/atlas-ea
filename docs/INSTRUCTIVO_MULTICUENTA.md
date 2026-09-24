# ATLAS EA — Instructivo: el bot en varias cuentas

Cada cuenta corre en **su propio contenedor**, totalmente aislado: su configuración,
su riesgo, sus logs. Podés parar, actualizar o borrar una cuenta sin tocar las demás.
El servidor (64 GB de RAM) aguanta con comodidad 10 o más cuentas a la vez.

```
Servidor SRPY186
├── atlas-ea          ← la cuenta original (demo 110545149)
├── atlas-demo2       ← ejemplo: otra demo
├── atlas-xm-real     ← ejemplo: cuenta real de XM
└── ...                  una por contenedor, sin límite práctico
```

---

## Qué necesitás por cada cuenta nueva

Tres datos que te da el broker al crear la cuenta (cualquier broker con MetaTrader 5):

1. **Login** (número de cuenta)
2. **Servidor** (ej: `MetaQuotes-Demo`, `XMGlobal-MT5 6` — figura en el mail del broker
   o en la app, en los datos de la cuenta)
3. **Contraseña** (la principal, no la "investor")

> 💡 En XM el nombre exacto del servidor aparece en el mail de bienvenida de la cuenta
> y en **Mi Cuenta → panel**. Si tenés dudas, en la app MT5 el servidor figura al lado
> del número de cuenta.

---

## Agregar una cuenta (5 minutos)

**1.** Entrá al servidor (por AnyDesk a la terminal, o desde la Mac con Tailscale
encendido):

```bash
ssh santarosa@100.112.44.111
```

**2.** Corré el asistente:

```bash
bash ~/atlas-ea/docker/agregar_cuenta.sh
```

**3.** Contestá las 5 preguntas: nombre corto (ej: `xm-real`), login, servidor,
contraseña (no se ve al escribirla — es normal) y riesgo por operación (Enter = 1,5%).

**4.** Esperá 2-3 minutos y verificá:

```bash
bash ~/atlas-ea/docker/cuentas.sh log xm-real
```

Tiene que aparecer `ATLAS EA v2.21 iniciado` y **una línea por símbolo** con sus
estrategias y su sesión, por ejemplo:

```
XAUUSD | SmartMoney | sesion LONDRES 08-17h = servidor 10-19h = tu hora (UTC-3) 04-13h
XAGUSD | SmartMoney | sesion LONDRES 08-17h = servidor 10-19h = tu hora (UTC-3) 04-13h
USDJPY | SmartMoney | sesion NUEVA YORK 08-13h = servidor 15-20h = tu hora (UTC-3) 09-14h
```

⚠️ Si alguna línea dice **`NINGUNA (no va a operar)`**, ese símbolo está en la cartera
pero sin estrategia asignada: revisá el `.env` de esa cuenta. Y si un símbolo cae en
`sesion SERVIDOR` sin que lo hayas pedido, es que no figura en ninguna lista de sesión.

Si aparece `authorized` en `cuentas.sh conexion xm-real`, la cuenta quedó conectada.
**Listo: opera sola 24/5.**

---

## Manejo diario

```bash
bash ~/atlas-ea/docker/cuentas.sh lista            # estado de todas
bash ~/atlas-ea/docker/cuentas.sh log NOMBRE       # diario del bot
bash ~/atlas-ea/docker/cuentas.sh conexion NOMBRE  # ¿conectada al broker?
bash ~/atlas-ea/docker/cuentas.sh parar NOMBRE     # apagar esa cuenta
bash ~/atlas-ea/docker/cuentas.sh arrancar NOMBRE  # encenderla de nuevo
bash ~/atlas-ea/docker/cuentas.sh borrar NOMBRE    # eliminarla (pide confirmación)
```

Cada cuenta también se ve en **la app MetaTrader 5 del celular**: agregá el login de
esa cuenta en la app (con la contraseña investor si solo querés mirar) y vas a ver sus
operaciones en tiempo real, cada cuenta por separado.

---

## Configurar cada cuenta distinto (opcional)

La configuración de cada cuenta vive en `~/atlas-ea/cuentas/NOMBRE.env`. Se puede
editar (con `nano` por ejemplo) y aplicar los cambios recreando el contenedor:

| Variable | Qué controla | Valor por defecto |
|---|---|---|
| `ATLAS_RISK` | Riesgo por operación (% del capital) | `1.5` |
| `ATLAS_DAILY_LOSS` | Límite de pérdida diaria (%) | `5.0` |
| `ATLAS_MAX_DD` | Freno de emergencia (% de caída desde el pico) | `30.0` |
| `ATLAS_SYMBOLS` | Qué símbolos carga el bot | `XAUUSD,USDJPY,XAGUSD` |
| `ATLAS_SMC_SYMBOLS` | Qué símbolos operan con Smart Money | `XAUUSD,USDJPY,XAGUSD` |
| `ATLAS_CRT_SYMBOLS` | Qué símbolos operan con CRT | *(vacío — restaba en backtest)* |
| `ATLAS_NY_SYMBOLS` | Qué símbolos operan en la sesión de Nueva York | `USDJPY` |
| `ATLAS_LONDON_SYMBOLS` | Qué símbolos operan en la sesión de Londres | `XAUUSD,XAGUSD` |
| `ATLAS_TG_TOKEN` · `ATLAS_TG_CHAT_ID` | Telegram: memos, alertas y aprobación (ver README). **Un bot por cuenta** | *(vacío = sin Telegram)* |
| `ATLAS_DECISION_MODE` | 0 automático · 1 confirmar por Telegram · 2 solo observar | `0` |

> Los "valores por defecto" son los que **compila el EA**. Si una variable no está en el
> `.env`, el entrypoint no escribe esa línea y manda el default del EA. Si la ponés,
> gana la del `.env` — así que si tocás `ATLAS_SYMBOLS` para sumar un símbolo, tenés que
> tocar **también** su lista de estrategia y su lista de sesión, o no va a operar.

Después de editar:

```bash
docker rm -f atlas-NOMBRE
bash ~/atlas-ea/docker/agregar_cuenta.sh   # o recreá con docker run usando el mismo .env
```

*(Más simple: borrá la cuenta con `cuentas.sh borrar` y volvé a agregarla con los
valores nuevos — son 2 minutos.)*

---

## Las reglas de oro

1. **NUNCA dos contenedores con el mismo login.** Dos bots sobre la misma cuenta se
   pisan las operaciones entre sí. El asistente lo controla y no te deja, pero vale
   saberlo: una cuenta = un contenedor.
2. **Cuenta real solo después de validar en demo.** El proceso de siempre: primero una
   demo del MISMO broker (los spreads y la ejecución cambian entre brokers), mínimo
   2-4 semanas, y recién entonces la real — arrancando con el riesgo más bajo.
3. **Si el broker es nuevo, verificá los nombres de los símbolos.** Algunos llaman
   `GOLD` al oro o usan sufijos (`XAUUSD.a`). Si el log dice que un símbolo no existe,
   editá `ATLAS_SYMBOLS` en el `.env` de esa cuenta con los nombres exactos.
4. **Las actualizaciones del bot no se aplican solas.** Cuando mejoremos el código y se
   reconstruya la imagen, cada cuenta se actualiza recreando su contenedor — una por
   una, cuando vos quieras.
5. **Un bot de Telegram por cuenta.** Si dos cuentas usan el mismo `ATLAS_TG_TOKEN`,
   los dos EAs leen el mismo chat y se roban los mensajes: un `APROBAR` lo puede agarrar
   la cuenta equivocada, y los IDs de los memos (`FD-aammdd-NNN`) se repiten entre
   cuentas. Creá un bot nuevo en @BotFather para cada una; el `ATLAS_TG_CHAT_ID` sí es
   el mismo en todas (el tuyo).

---

## Preguntas rápidas

**¿Cuántas cuentas aguanta el servidor?** Cada una usa hasta 3 GB de RAM (limitado).
Con 64 GB, más de 10 sin despeinarse.

**¿Puedo tener brokers distintos?** Sí — cualquier broker con MetaTrader 5. Cada
cuenta apunta a su propio servidor.

**¿Puedo tener configuraciones distintas por cuenta?** Sí — una demo agresiva y una
real conservadora, por ejemplo. Cada `.env` es independiente.

**¿Qué pasa si el servidor se reinicia?** Todos los contenedores vuelven solos
(`--restart unless-stopped`), se reconectan y re-adoptan sus posiciones.

**¿El monitoreo cubre las cuentas nuevas?** Sí — el vigilante de salud revisa todos
los contenedores `atlas-*` cada 30 minutos y avisa si alguno se cae o se desconecta.
