<p align="center"><img src="docs/logo.svg" width="96" alt="GDC Metadata"></p>

# GDC Metadata

**Sitio web: [https://gordas.dev/gdc-metadata/](https://gordas.dev/gdc-metadata/)**

Lee cámara, objetivo, exposición, balance de blancos, perfil de imagen y timecode de carpetas multicámara, muestra el origen de cada valor y los envía al Media Pool de DaVinci Resolve. Todo queda en tu Mac; los originales no se modifican.

**[Descargar para macOS](https://github.com/gordasgdc/gdc-metadata/releases/download/v0.2.0/GDCMetadata-0.2.0.dmg)** — Versión 0.2.0 · gratis · DMG firmado y notarizado

[English](README.md) · [Română](README.ro.md) · [Español](README.es.md) · Guía de uso: [EN](docs/guide.en.md) · [RO](docs/guide.ro.md) · [ES](docs/guide.es.md)

Manual (PDF): [RO](docs/manual/pdf/manual-ro.pdf) · [EN](docs/manual/pdf/manual-en.pdf) · [ES](docs/manual/pdf/manual-es.pdf) — https://gordas.dev/gdc-metadata/

¿Ya tienes la 0.1.0? Esa versión no tiene actualizador: instala una vez el nuevo DMG (arrastra la app sobre Applications y elige Reemplazar). Después usa el menú de la app → Buscar actualizaciones…

![](site/img/02_default_en.png)

## Gamut de entrada y curva de transferencia

Arriba en el inspector, por clip: el gamut de entrada y la curva de transferencia que grabó la cámara, cada uno con su origen, para saber qué entrada elegir en la gestión de color. Verificado: MP4 Canon Cinema EOS / EOS R con la pista de metadatos cndm — Canon Log 2 frente a Canon Log 3 con Cinema Gamut, confirmado frente a DaVinci Resolve (decodificado por GDC; Canon no documenta el formato). Cuando el archivo no contiene nada, ambos quedan No disponible y no se asigna nada; las etiquetas del contenedor y los indicios de los metadatos de la cámara se muestran aparte y no se presentan como perfil de la cámara. Fijar Input Color Space en Resolve es una acción separada, explícita y con confirmación, en proyectos DaVinci YRGB Color Managed, y nunca sobrescribe una elección existente.

## Enviar a Resolve

![](site/img/09_resolve_en.png)

- Los campos vacíos de Resolve se escriben; los valores existentes se conservan; un clip en varios bins se omite por ambiguo (verificado en Resolve tras reabrir el proyecto).
- El CSV es una alternativa, pero la importación de Resolve puede sobrescribir los valores existentes y, con nombres de archivo duplicados, todos los clips con ese nombre reciben los mismos valores. Opciones verificadas: Match using filename activado, Timecode inicio/fin desactivado.
- Junto a cada clip se escribe un sidecar <clip>.gdc-metadata.json; los originales solo se leen.

## Movimiento y estabilización

Los datos de movimiento detectados se listan con su origen y la nota «Compatibilidad con Gyroflow sin verificar». No se ofrece estabilización hasta demostrar una ruta antes/después en Resolve. Estado ilustrativo, datos sintéticos.

## Requisitos

- macOS 14 o posterior.
- ExifTool (por ejemplo: brew install exiftool).
- Python 3 de las Xcode Command Line Tools — solo para enviar a Resolve.
- DaVinci Resolve abierto, con External scripting en Local — solo para enviar a Resolve.

## Build

```sh
export GDC_BUILD_ROOT=/path/to/build-folder
sh scripts/build_app.sh
GDC_SAMPLE_CLIP=/path/to/clip.mp4 GDC_SYNTH_DIR=/path/to/dir cargo test --manifest-path core/Cargo.toml
```

Licencia MIT · © 2026 Cristi Gordaș · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · Todas las imágenes usan datos de demostración sintéticos.
