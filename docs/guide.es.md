# GDC Metadata — Guía de uso

## Carpeta → inspector → Media Pool

1. **Abre una carpeta** (botón de carpeta de la barra). La app la escanea en solo lectura y lista los clips: cámara, timecode y más.
2. **Inspector.** Selecciona un clip: cámara, objetivo, balance de blancos, exposición y perfil de imagen. Cada valor muestra su origen (etiqueta del clip, derivado, no disponible). Busca por campo o valor; el aviso explica por qué coincide un clip.
3. **Enviar a Resolve.** Abre antes un proyecto en Resolve. La hoja previsualiza, por clip, qué se escribe, qué se conserva y qué es idéntico.
4. **Aplicar al Media Pool** escribe los valores.

## Gamut de entrada y curva de transferencia

Los dos valores superiores del inspector indican qué entrada elegir en la gestión de color: por ejemplo un clip Canon C50 muestra **Cinema Gamut** + **Canon Log 2** (leído de la pista `cndm` del archivo) — en Resolve eliges *Canon Cinema Gamut / Canon Log 2*; un clip Canon Log 3 muestra **Canon Log 3**. Cada valor tiene su origen; sin evidencia la fila dice **No disponible** y no se asigna nada. Resolve detecta solo muchos clips Canon al importar. **Aplicar al Media Pool** solo escribe notas informativas (Gamma Notes / Color Space Notes); **Fijar espacio de entrada…** es una acción separada y con confirmación que cambia el procesado de color, funciona en proyectos DaVinci YRGB Color Managed y nunca sobrescribe una elección existente. Manual: Project Settings ▸ Color Management ▸ DaVinci YRGB Color Managed, luego Media Pool ▸ clic derecho en el clip ▸ Input Color Space.

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

## Varios clips, carpetas, segundo lote

- **Arrastra clips o una carpeta** sobre la ventana, en un solo gesto y en cualquier número. O usa **Elegir carpeta…** (⌘O) y selecciona varios archivos y carpetas a la vez.
- Una importación nueva se **añade** a la lista; el primer lote se conserva. **File → Vaciar lista** empieza de cero.
- La barra inferior indica cuántos clips se importaron; si se rechazó algún archivo, pulsa «importados · rechazados» para ver el motivo de cada uno.
- Los clips con el mismo nombre de carpetas distintas siguen separados.

## Versión y actualizaciones

- La versión instalada está en la barra inferior y en **Acerca de GDC Metadata** (versión y build).
- **Buscar actualizaciones…** (menú de la app) siempre responde: versión nueva, «Estás al día» o «No se pudo buscar» con el motivo. **Actualizar ahora** descarga, verifica, instala y reinicia la app.
- Si vienes de la 0.1.0 (sin actualizador): instala una vez el nuevo DMG; después actualizas desde la app.

## Manual completo

- Manual PDF completo: botón / menú **Ayuda**, o https://gordas.dev/gdc-metadata/GDC-Metadata-Manual-es.pdf


**Lotes (0.3.0).** Selecciona con clic/Mayús/⌘/⌘A, pulsa **Aceptar para exportar** (cada clip conserva su par; reversible), luego **Exportar N clips** o **Enviar N a Resolve**, exactamente sobre la selección. **Quitar de la lista** (⌘⌫) y **Vaciar lista** (⇧⌘⌫) solo afectan a la lista. Lo que los lectores no encuentran aparece como **No detectado**, no como «falta». Sony: curva y gamut se leen de los metadatos incrustados; S-Gamut3.Cine ≠ S-Gamut3.
