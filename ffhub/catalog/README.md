# Catálogo 3D

Un directorio por pieza, un `manifest.json` por pieza. El cuerpo base va por avatar.

```
catalog/
  body/
    102000015/
      manifest.json
      mesh.glb
  torso/
    203000196/
      manifest.json
      mesh.glb
  head/
    211000087/
      manifest.json
      mesh.glb
```

## Contrato

El manifiesto es lo único que el ensamblador conoce. Se valida al cargar, no al exportar:

| Campo | Obligatorio | Efecto |
| --- | --- | --- |
| `item_id` | sí | Clave que devuelve `/info` en `profileInfo.clothes`. |
| `type` | sí | `feet`, `legs`, `torso`, `face_paint`, `head`, `hair`, `accessory`. Ordena el montaje. |
| `mesh` | sí | Archivo dentro del directorio de la pieza; una ruta que salga de él se rechaza. |
| `mount` | no | `position`, `rotation_euler_deg`, `scale` en espacio del cuerpo. |
| `hides` | no | Nodos del cuerpo que la pieza cubre: `body:head_skin`. |
| `compatible_avatars` | no | Vacío o ausente = sirve para cualquier cuerpo. |
| `catalog_version` | recomendado | Entra en la clave de reutilización; súbelo al corregir una pieza. |

`manifest.example.json` es una plantilla. El loader sólo lee archivos llamados
`manifest.json`, así que una plantilla en el mismo directorio no lo rompe.

## Reglas

- Un `item_id` duplicado, un tipo desconocido, una malla ausente o una ruta que
  escape del directorio dejan el catálogo inválido y el worker falla cerrado.
- Todas las piezas deben compartir `catalog_version`; si se mezclan, el catálogo
  se marca inválido.
- Las texturas van dentro del GLB de la pieza. El exportador no busca archivos
  de imagen sueltos, así que una pieza con textura externa sale sin textura.
- Las dos piezas de cabeza del ejemplo (211000087 y 211000303) conviven: no hay
  regla de exclusión todavía, se montan ambas en el orden del tipo.

## Primer catálogo real: Golden Sakura

`scripts/import_bundle.py` separa un bundle de la comunidad —una sola escena con
los nodos `Object_0…`, sin esqueleto ni nombres útiles— en una entrada por pieza,
cociendo la transformación de mundo en los vértices:

```bash
.venv/bin/python scripts/import_bundle.py ../.incoming/glb/golden_sakura.glb --dry-run
.venv/bin/python scripts/import_bundle.py ../.incoming/glb/golden_sakura.glb
```

El mapeo de este bundle, decidido por altura y por textura:

| Parte | Entrada | Tipo | Altura |
| --- | --- | --- | --- |
| `Object_0` (cara y piel) | `body/golden_sakura` | cuerpo | 0.00–2.29 |
| `Object_1` | `feet/gsk_feet` | botas | -0.02–0.20 |
| `Object_2` | `legs/gsk_legs` | pantalón | 0.14–1.36 |
| `Object_3` | `torso/gsk_torso` | kimono | 1.22–2.05 |
| `Object_4` | `head/gsk_head` | adorno de cabeza | 1.97–2.41 |
| `Object_5` | `hair/gsk_hair` | pelo | 1.99–2.41 |

Todos comparten `catalog_version: golden-sakura-1`, y cada GLB lleva su propia
textura embebida (el importador falla si alguna se pierde).

Los ids `gsk_*` son del bundle, **no** ids de item de Free Fire: `/info` devuelve
ids numéricos, así que hoy estas piezas sólo se montan pasando `--items` a mano.

### Apuntarlo a un perfil real

`scripts/bind_profile.py` hace el renombrado completo a partir de un `/profile`
guardado — un `mv` por entrada y el manifiesto reescrito dentro:

```bash
curl -s -H "Authorization: Bearer $FFHUB_TOKEN" -H 'content-type: application/json' \
     -d '{"uid":"11807385","region":"us"}' https://hub.example.com/profile > profile.json
.venv/bin/python scripts/bind_profile.py profile.json
```

Un perfil guardado contra este catálogo no sabe qué prenda es cada id (`type`
sale `unknown` porque lo rellena el catálogo), así que los slots se pasan a mano
con `--map`, por tipo o por id actual, repetible:

```bash
.venv/bin/python scripts/bind_profile.py profile.json \
  --map feet=205000070 --map legs=204000103 --map gsk_torso=203000196 \
  --map head=211000087 --map hair=214000053
```

Antes del primer `mv` se exige: `avatar_id` de 6–20 dígitos, un id de 4–20
dígitos por cada uno de los cinco slots, ids distintos entre sí y destino libre.
Si algo falta sale con código 2 (perfil), 3 (el catálogo no parece el bundle sin
enlazar, por ejemplo porque ya se ejecutó) o 4 (conflicto), y no mueve nada.
`--dry-run` imprime el plan sin tocar disco.

Ninguna pieza lleva `hides`: el cuerpo del bundle ya trae la piel completa y las
prendas se superponen encima, así que no hay nodo del cuerpo que ocultar.
