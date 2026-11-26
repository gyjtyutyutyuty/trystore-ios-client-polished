# FFHub — outfit 3D desde un UID

Panel en Sites, backend y worker en el VPS. El jugador escribe un UID, ve las
prendas que lleva y descarga un GLB con el personaje vestido y las texturas
integradas.

```
panel (Sites Worker)  ──/api/*──▶  API (FastAPI, 127.0.0.1:8890)  ──▶  Free Fire API Hub
                                        │
                                   cola SQLite
                                        │
                                   worker (GLB)  ──▶  /var/lib/ffhub/files/<reuse>.glb
```

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

| Variable | Obligatoria | Uso |
| --- | --- | --- |
| `FREE_FIRE_API_KEY` | sí | Clave del proveedor. Sólo en `/etc/ffhub/env`. |
| `FFHUB_TOKEN` | sí | Bearer que exige la API; lo tiene el Worker de Sites. |
| `FFHUB_DATA_DIR` | no | SQLite, GLB publicados y temporales. Por defecto `./data`. |
| `FFHUB_CATALOG_DIR` | no | Raíz del catálogo 3D. Por defecto `./catalog`. |
| `FFHUB_EXPORTER_VERSION` | no | Entra en la clave de reutilización. |
| `FFHUB_MAX_GLB_BYTES` | no | Tope de publicación, 256 MB por defecto. |

## API

Todas las rutas salvo `/healthz` piden `Authorization: Bearer $FFHUB_TOKEN`.

| Ruta | Qué hace |
| --- | --- |
| `POST /profile` | `{uid, region}` → nombre, región devuelta, avatar, prendas con tipo y URL de miniatura. |
| `GET /thumbnail/{item_id}` | Miniatura del proveedor, cacheada por ID con su `Content-Type` real. `X-Cache: hit\|miss`. |
| `POST /jobs` | `{uid, region}` o `{uid, region, avatar_id, items}`. Devuelve `{job, created}`. |
| `GET /jobs/{id}` | `queued`, `generating`, `ready`, `partial`, `error` + `progress` y `detail`. |
| `GET /files/{reuse_key}.glb` | El GLB publicado. |

`region` acepta `us`, `br`, `na`, `latam`, `sg`, `id`, `th`, `vn`, `my`. US, BR,
NA y LATAM se envían al proveedor como `br`; la región que devuelve el perfil se
guarda aparte y es la que se muestra.

### Errores con nombre

`invalid_uid`, `invalid_region`, `profile_not_found`, `clothes_unavailable`,
`clothes_empty`, `avatar_not_in_catalog`, `provider_rate_limited` (con
`Retry-After`), `provider_auth`, `provider_bad_response`, `file_not_ready`.

Un `clothes` ausente y un `clothes: []` son respuestas distintas: la primera es
`unavailable`, la segunda `empty`.

### Reutilización

La clave es `sha256(avatar, prendas ordenadas, versión de catálogo, versión de
exportador)`. Si ya existe un trabajo en cola o generando con esa clave, el panel
recibe el mismo trabajo en vez de uno nuevo. Si existe un GLB publicado, se
devuelve al instante.

## Catálogo

Ver [`catalog/README.md`](catalog/README.md) y
[`catalog/manifest.schema.json`](catalog/manifest.schema.json). Hay un bundle
real importado: cuerpo `golden_sakura` más cinco piezas `gsk_*` (botas,
pantalón, kimono, adorno de cabeza, pelo), generadas con
`scripts/import_bundle.py`.

Esos ids son del bundle, no ids de item de Free Fire. Con un UID real el perfil
devuelve ids numéricos, así que hasta renombrar directorios y manifiestos a los
que publique `/info`, `/jobs` responde `avatar_not_in_catalog`; para probar el
montaje sin proveedor, `scripts/e2e.py --avatar-id golden_sakura --items
 gsk_feet,gsk_legs,gsk_torso,gsk_head,gsk_hair`.

## Despliegue

1. `/opt/ffhub` con el código y `.venv`; `useradd -r -s /usr/sbin/nologin ffhub`.
2. `/etc/ffhub/env` a 0640 root:ffhub con las dos claves.
3. `deploy/ffhub-api.service` y `deploy/ffhub-worker.service` en `/etc/systemd/system`, `systemctl enable --now`.
4. nginx con `deploy/nginx.conf`, TLS de Let's Encrypt.
5. Panel: `sites_deploy` con `panel/deploy.json` y dos secretos en Sites:
   `BACKEND_URL` (https://hub.example.com) y `HUB_TOKEN` (el mismo `FFHUB_TOKEN`).
   El navegador nunca ve ninguno de los dos.

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
