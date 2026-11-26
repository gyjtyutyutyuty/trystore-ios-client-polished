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
