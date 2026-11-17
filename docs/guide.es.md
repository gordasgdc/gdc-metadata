# GDC Metadata — Guía de uso

## Carpeta → inspector → Media Pool

1. **Abre una carpeta** (botón de carpeta de la barra). La app la escanea en solo lectura y lista los clips: cámara, timecode y más.
2. **Inspector.** Selecciona un clip: cámara, objetivo, balance de blancos, exposición y perfil de imagen. Cada valor muestra su origen (etiqueta del clip, derivado, no disponible). Busca por campo o valor; el aviso explica por qué coincide un clip.
3. **Enviar a Resolve.** Abre antes un proyecto en Resolve. La hoja previsualiza, por clip, qué se escribe, qué se conserva y qué es idéntico.
4. **Aplicar al Media Pool** escribe los valores.

## Qué hace «Aplicar» (verificado en Resolve, tras cerrar y reabrir el proyecto)

- Campo vacío → se escribe.
- Campo que ya tiene valor → se conserva (no se sobrescribe).
- El mismo clip en más de un bin → ambiguo, no se aplica.
- Los clips se emparejan por la ruta real del archivo, así que también coinciden las carpetas alcanzadas mediante enlaces.

## CSV como alternativa

- Guarda el CSV desde la hoja y en Resolve: File → Import Metadata To → Media Pool…
- Opciones verificadas: marca **Match using filename**; deja sin marcar **Match using clip start and end Timecode** (marcada, Resolve no encontró coincidencias con nuestro CSV); Reel Name sin marcar; en la fusión **Only update metadata items with entries in the source file**.
- **Aviso:** la importación sobrescribe los valores existentes.
- **Nombres de archivo duplicados:** Resolve empareja por nombre, así que todos los clips con ese nombre (en cualquier bin, incluso de carpetas distintas) reciben los mismos valores. Usa «Aplicar al Media Pool» para evitarlo.

## Movimiento y estabilización

- El inspector lista los datos de movimiento detectados (telemetría en el clip, registros externos, proyectos .gyroflow) y dónde se encontró cada uno.
- Las fuentes se muestran como **Compatibilidad con Gyroflow sin verificar**. No se ofrece estabilización: aún no hay una ruta antes/después demostrada en Resolve.
