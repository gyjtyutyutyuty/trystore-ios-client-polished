# FFHub — outfit 3D desde un UID

El jugador escribe un UID, ve las prendas que lleva y descarga un GLB con el
personaje vestido y las texturas integradas.

Todo corre en Cloudflare, sin VPS: el Worker del panel llama al proveedor, fusiona
los GLB del catálogo y sirve el resultado.

```
panel + backend (Workers)  ──▶  Free Fire API Hub
        │
   catálogo como assets (GLB con textura)  ──▶  fusión en memoria ──▶  /api/outfits/<avatar>/<ids>.glb
```

La descarga no se guarda: la URL lleva el outfit completo (`avatar` + ids), así
que el Worker lo reconstruye igual en cada petición y el enlace compartido no
caduca. `app/` sigue siendo la implementación FastAPI (cola SQLite, worker en
systemd) para el VPS y para los scripts de línea de comandos; `deploy/` la
despliega.

## Arranque rápido

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp deploy/env.example env && $EDITOR env          # claves, nunca al repo
set -a && . ./env && set +a
.venv/bin/uvicorn app.asgi:app --host 127.0.0.1 --port 8890
.venv/bin/python -m app.worker --poll 2           # en otra terminal
.venv/bin/python -m pytest                        # 61 tests, sin red
```

El worker acepta `--once` para drenar un solo trabajo y salir.

## Un GLB real, punta a punta

```bash
.venv/bin/python scripts/e2e.py --uid 11807385 --region us
```

Hace las cinco etapas en un proceso —config, `/info`, catálogo, trabajo, build—
y termina imprimiendo la ruta y el tamaño del GLB, o exactamente qué manifiesto
falta. Códigos de salida: `0` listo/parcial, `2` config, `3` catálogo, `4`
proveedor, `5` build. Con `--json` sale además una línea con uid, avatar, ids,
trabajo y archivo.

Para reconstruir sin llamar al proveedor (los ids que ya conoces):

```bash
.venv/bin/python scripts/e2e.py --uid 11807385 \
  --avatar-id 102000015 \
  --items 211000087,211000303,214000053,203000196,204000103,205000070
```

## Variables de entorno

El camino por defecto (Worker) lee estos secretos de Sites:

| Secreto de Sites | Obligatoria | Uso |
| --- | --- | --- |
| `FREE_FIRE_API_KEY` | sí | Clave del proveedor. Vive en Sites → Secrets; el navegador nunca la ve. |
| `PANEL_TOKEN_KEY` | sí | Firma las sesiones del panel. El mismo valor en el licence Worker (`wrangler secret put`). Sin ella el panel no deja entrar a nadie. |
| `PANEL_ADMIN_PASSWORD` | no | Acceso del dueño, 12 caracteres mínimo. Sin ella el formulario de administrador no aparece. |
| `FIRE_API_BASE` | no | Base del proveedor. Por defecto `https://developers.freefirecommunity.com/api/v1`. |
| `JOBS_PER_CLIENT_HOUR` | no | Tope por cliente en `/api/jobs`. Por defecto 12. |
| `JOBS_PER_DAY` | no | Tope global diario de trabajos. Por defecto 400. |

No hay `BACKEND_URL` ni `HUB_TOKEN`: el Worker no proxya a ningún servidor.

## Acceso: el panel es privado

Todo el panel (assets y API) exige una sesión. La sesión es un token
HMAC-SHA256 en una cookie `HttpOnly; Secure; SameSite=Lax`, de quince minutos
como máximo, firmado con `PANEL_TOKEN_KEY`. Esa clave no está en la app: quien
descompile la IPA obtiene la URL y nada con lo que firmar.

Dos formas de entrar:

1. **Desde la app** (clientes con licencia). La app pide
   `POST /api/v1/panel/token` al licence Worker con una **assertion de App
   Attest** de ese dispositivo; el Worker comprueba licencia, dispositivo,
   desafío de un solo uso y contador de firmas, y devuelve un token de diez
   minutos. La app abre `https://<panel>/#t=<token>`; el fragmento no viaja al
   servidor ni queda en logs, y la página lo canjea por la cookie y lo borra de
   la barra de direcciones.
2. **Administrador** (tú). `PANEL_ADMIN_PASSWORD` en `/login`, sesión de ocho
   horas. Cinco intentos por minuto y cliente: el resto, 429.

El formato del token está duplicado a propósito en
`panel/lib/session.js` (verifica) y `cloudflare/panel-token-format.js` (firma);
`cloudflare/test/panel-token.test.mjs` alimenta uno con el otro para que no se
separen.

### Cuotas reales

`/api/jobs` gasta la clave del proveedor, así que se limita dos veces: por
cliente y por día, en D1 (`env.DB`), compartido entre isolates. El resto de
rutas sólo tienen un tope anti-bucle. Si D1 falla, el limitador cae al contador
en memoria del isolate y lo avisa por consola: un contador roto no debe
transformarse en barra libre.

La variante FastAPI (`app/`, en un VPS) usa además `FFHUB_TOKEN` como bearer,
`FFHUB_DATA_DIR`, `FFHUB_CATALOG_DIR`, `FFHUB_EXPORTER_VERSION` y
`FFHUB_MAX_GLB_BYTES`; ver `deploy/env.example`.

## API

### Worker, sin VPS

El navegador no lleva token: el Worker guarda la clave y sólo atiende rutas
fijas.

| Ruta | Qué hace |
| --- | --- |
| `POST /api/profile` | `{uid, region}` → nombre, avatar, prendas con tipo, `in_catalog` y miniatura. |
| `GET /api/thumbnail/{item_id}` | Miniatura del proveedor, cacheada por ID. |
| `POST /api/jobs` | `{uid, region}` o `{uid, region, avatar_id, items}` → trabajo ya resuelto (`ready`/`partial`). |
| `GET /api/outfits/{avatar}/{ids}.glb` | El GLB. La URL nombra el outfit completo, así que se reconstruye igual. |

`region` acepta `us`, `br`, `na`, `latam`, `sg`, `id`, `th`, `vn`, `my`. US, BR,
NA y LATAM se envían al proveedor como `br`; la región que devuelve el perfil se
guarda aparte y es la que se muestra.

Errores con nombre del Worker: `provider_not_configured`, `invalid_uid`,
`invalid_region`, `invalid_avatar_id`, `invalid_item_id`, `avatar_not_in_catalog`,
`profile_not_found`, `provider_rate_limited` (con `Retry-After`), `provider_auth`,
`provider_bad_response`, `rate_limited`, `forbidden_origin`, `body_too_large`,
`method_not_allowed`, `not_found`, `internal_error`.

Un `clothes` ausente y un `clothes: []` son respuestas distintas: la primera es
`unavailable`, la segunda `empty`.

### FastAPI, variante VPS (opcional)

Todas las rutas salvo `/healthz` piden `Authorization: Bearer $FFHUB_TOKEN`.

| Ruta | Qué hace |
| --- | --- |
| `POST /profile` | Igual que en el Worker, más `requested_region` y `catalog_problems`. |
| `GET /thumbnail/{item_id}` | Miniatura cacheada con su `Content-Type` real. `X-Cache: hit\|miss`. |
| `POST /jobs` | `{uid, region}` o `{uid, region, avatar_id, items}`. Devuelve `{job, created}`. |
| `GET /jobs/{id}` | `queued`, `generating`, `ready`, `partial`, `error` + `progress` y `detail`. |
| `GET /files/{reuse_key}.glb` | El GLB publicado. |

### Reutilización

La clave es `sha256(avatar, prendas ordenadas, versión de catálogo, versión de
exportador)`.

- Worker: no hay cola ni ficheros. La descarga se pide por
  `/api/outfits/<avatar>/<ids>.glb` y se regenera en cada petición, byte a byte
  idéntica; la clave se usa como nombre del archivo.
- FastAPI: la misma clave identifica el trabajo y el GLB publicado; dos jugadores
  con el mismo outfit comparten trabajo y archivo.

## Catálogo

Ver [`catalog/README.md`](catalog/README.md) y
[`catalog/manifest.schema.json`](catalog/manifest.schema.json). Hay un bundle
real importado: cuerpo `golden_sakura` más cinco piezas `gsk_*` (botas,
pantalón, kimono, adorno de cabeza, pelo), generadas con
`scripts/import_bundle.py`.

Esos ids son del bundle, no ids de item de Free Fire. Con un UID real el perfil
devuelve ids numéricos, así que hay que enlazarlo con
`scripts/bind_profile.py profile.json` (`--map` por slot y `--skip` para un
hueco vacío, ver [`catalog/README.md`](catalog/README.md)); sin ese enlace
`/jobs` responde `avatar_not_in_catalog`.

**Estado actual: demostración.** El catálogo está enlazado al perfil del UID
`11807385` (avatar `102000015`, prendas `205000070`, `204000103`, `203000196`,
`214000000`, `211000303`) pero las mallas siguen siendo las de Golden Sakura, y
el panel lo dice en cabecera. `211000087` (máscara) no tiene malla y no se
dibuja. Para sustituirla de verdad hace falta un GLB del look real (cuerpo más
prendas equipadas, texturas incrustadas): `import_bundle.py` → tabla de partes
→ `bind_profile.py` con estos mismos ids → `sync_catalog.py` → deploy.

Para probar el montaje sin proveedor: `scripts/e2e.py --avatar-id golden_sakura
--items gsk_feet,gsk_legs,gsk_torso,gsk_head,gsk_hair` sigue valiendo mientras
el catálogo no esté enlazado; ya enlazado, usa los ids del perfil.

## Despliegue

### Cloudflare, sin VPS (camino por defecto)

1. Copia el catálogo junto al panel y escribe el índice que lee el Worker:

   ```bash
   .venv/bin/python scripts/sync_catalog.py
   ```

   `panel/public/catalog/` es salida de build (git-ignored). Hay que regenerarla
   antes de cada despliegue, también después de `bind_profile.py`.

2. Despliega con `panel/deploy.json`: el Worker, sus cinco módulos de `lib/` y
   `public/` como assets. La base `DB` (D1) tiene que existir para que las
   cuotas sean compartidas; el despliegue la engancha.
3. Secretos del proyecto en Sites → Secrets: `FREE_FIRE_API_KEY`,
   `PANEL_TOKEN_KEY` y `PANEL_ADMIN_PASSWORD` (y `FIRE_API_BASE` si tu
   proveedor no es el de por defecto).
4. En el **licence Worker**, el mismo `PANEL_TOKEN_KEY` (`wrangler secret put
   PANEL_TOKEN_KEY`) y despliégalo junto al feed worker, que ahora reenvía
   `/api/patches/trystore/panel-token`.
5. Publica el entorno y comprueba: `GET /` sin cookie devuelve la pantalla de
   acceso, `POST /api/profile` sin cookie devuelve `401 session_required`, y
   con sesión `POST /api/jobs` devuelve `ready`/`partial` con `download_url`.

Sin la clave del proveedor, `/api/profile`, `/api/jobs` con UID y
`/api/thumbnail/*` responden `provider_not_configured`; el ensamblado explícito
sigue funcionando. Sin `PANEL_TOKEN_KEY`, nadie entra: el panel falla cerrado y
la pantalla de acceso lo dice.

### Variante VPS (opcional)

Sólo hace falta si quieres la cola SQLite y el worker en systemd (`app/`). El
panel no la necesita.

1. `/opt/ffhub` con el código y `.venv`; `useradd -r -s /usr/sbin/nologin ffhub`.
2. `/etc/ffhub/env` a 0640 root:ffhub con `FREE_FIRE_API_KEY` y `FFHUB_TOKEN`.
3. `deploy/ffhub-api.service` y `deploy/ffhub-worker.service` en
   `/etc/systemd/system`, `systemctl enable --now`.
4. nginx con `deploy/nginx.conf`, TLS de Let's Encrypt.

## Límites conocidos

- Exportación estática en pose fija; no hay esqueleto ni animación.
- Sin reglas de exclusión entre dos piezas del mismo tipo: se montan ambas.
- Las texturas deben venir dentro del GLB de cada pieza. Pillow es obligatorio:
  sin él trimesh descarta las imágenes al cargar y el GLB sale sin texturas.
- La clave de reutilización no cambia si cambia el contenido de una malla, sólo
  si subes `catalog_version`. Súbela al corregir una pieza.
- Los nodos de una malla exportada desde el juego suelen llamarse `Object_0`,
  `Object_1`… Si el cuerpo no trae nombres estables, `hides` no puede apuntar a
  una parte concreta: conviene renombrar los nodos del cuerpo base una vez.
- Una exportación a la vez por worker; el techo de memoria está en la unit, no
  medido todavía con mallas reales.
