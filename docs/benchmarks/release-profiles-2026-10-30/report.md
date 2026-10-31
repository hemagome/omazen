# Comparación de perfiles de release

Fecha: 2026-10-30, America/Mexico_City. Código: Omazen `1.6.2`, Rust/Cargo `1.99.1`, `sha2 0.11.1`.

## Resultado y recomendación

Hay un beneficio claro de tamaño y una mejora pequeña de tiempo en un comando: **`strip = "symbols"` más `lto = "thin"`** reduce el ejecutable un 20.5 % y el payload comprimido un 9.6 %. ThinLTO mejora `doctor` aproximadamente un 4–5 % en las dos series de confirmación, equivalentes a unos **0.04 ms**. No se observa una mejora repetible en `sync` ni una mejora perceptible que pueda atribuirse a la interfaz de Zen.

Esta combinación es la recomendación si se desea un ajuste equilibrado y sencillo. Mantendría `opt-level = 3`, `codegen-units = 16` y `panic = "unwind"`. Si se busca exclusivamente una reducción mínima de riesgo y tiempo de compilación, basta con `strip = "symbols"`: ahorra un 20 % y la sección `.text` es idéntica a la del ejecutable original.

`opt-level = "s"` es una alternativa razonable si se prioriza tamaño: reduce el ejecutable un 28.7 % sin una regresión de tiempo consistente en estas mediciones. `"z"` reduce más, pero aumenta el costo de CPU de `doctor`. No recomiendo `panic = "abort"` para esta mejora: cambia el comportamiento ante un panic, y las pruebas de rutas normales no demuestran equivalencia del desenrollado y la limpieza de recursos.

**No se aplicó ningún perfil al proyecto ni se reemplazó la instalación activa.** El binario baseline del estudio coincide byte por byte con el instalado (`d81446c19214fd15c00f00fb6afb888ae910b2a5d2e19e5078a7aa2d6468e9d4`).

## Variantes, tamaño y primera serie

Todas las variantes salvo baseline incluyen `strip = "symbols"`. `size_s`, `size_z` y `abort` parten de ThinLTO con una unidad de compilación. Las otras opciones no indicadas conservan los valores predeterminados de release.

Las latencias son medianas de la primera serie en tmpfs (300 muestras por comando corto; 24 para `report`). No se mezclan con las series posteriores: la frecuencia del procesador y la carga ambiental pueden variar entre series. Los tiempos de compilación son **una sola compilación limpia por variante**, sin red y con caché de fuentes de dependencias; son orientativos.

| Variante | Ajuste adicional | Ejecutable KiB | Cambio | gzip KiB | Build s | sync ms | doctor ms | report ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| baseline | Predeterminado, sin strip | 818.1 | +0.0 % | 345.1 | 6.15 | 0.823 | 1.173 | 422.5 |
| strip | Solo símbolos | 654.6 | -20.0 % | 310.9 | 6.13 | 0.842 | 1.157 | 421.1 |
| cgu1 | 1 unidad | 640.3 | -21.7 % | 304.8 | 6.92 | 0.819 | 1.155 | 421.9 |
| thin | ThinLTO, 16 unidades | 650.2 | -20.5 % | 311.8 | 7.79 | 0.815 | 1.098 | 421.4 |
| thin1 | ThinLTO, 1 unidad | 642.3 | -21.5 % | 307.9 | 8.80 | 0.840 | 1.094 | 422.4 |
| fat1 | FatLTO, 1 unidad | 602.4 | -26.4 % | 295.5 | 10.72 | 0.839 | 1.148 | 421.4 |
| size_s | `opt-level="s"` | 583.7 | -28.7 % | 280.4 | 8.33 | 0.826 | 1.152 | 422.2 |
| size_z | `opt-level="z"` | 555.6 | -32.1 % | 269.6 | 7.60 | 0.844 | 1.198 | 421.3 |
| abort | `panic="abort"` | 614.3 | -24.9 % | 293.3 | 8.52 | 0.843 | 1.114 | 421.2 |

gzip mide únicamente el ejecutable, con nivel 6 y timestamp cero. Es un indicador del payload comprimido, **no el tamaño del archivo completo de release**, que también incluye código y documentación.

FatLTO reduce más el tamaño que ThinLTO, pero tarda aproximadamente 10.7 s frente a 7.8 s en estas compilaciones y no mejora de manera consistente el tiempo frente a ThinLTO. Una sola unidad de compilación tampoco aporta una ventaja clara adicional. Las variantes cgu1, thin1 y abort recibieron la misma primera serie y los 26 contratos; no se incluyeron en las dos confirmaciones adicionales.

## Confirmaciones independientes

En tmpfs se midieron 1,800 muestras por comando y variante en 30 rondas. En Btrfs se midieron otras 800 en 20 rondas, manteniendo los ejecutables originales y moviendo los archivos de estado y perfiles desechables al filesystem del proyecto. Se usaron semillas distintas para el orden aleatorio.

| Variante | tmpfs sync p50 / p95 ms | tmpfs doctor p50 / p95 ms | Btrfs sync p50 / p95 ms | Btrfs doctor p50 / p95 ms |
|---|---:|---:|---:|---:|
| baseline | 0.680 / 0.872 | 0.945 / 1.161 | 0.772 / 0.950 | 0.968 / 1.224 |
| strip | 0.681 / 0.819 | 0.943 / 1.159 | 0.776 / 0.930 | 0.957 / 1.159 |
| thin | 0.677 / 0.849 | 0.903 / 1.126 | 0.771 / 0.976 | 0.926 / 1.160 |
| fat1 | 0.671 / 0.845 | 0.927 / 1.079 | 0.760 / 0.911 | 0.952 / 1.130 |
| size_s | 0.673 / 0.793 | 0.936 / 1.132 | 0.782 / 0.941 | 0.964 / 1.202 |
| size_z | 0.682 / 0.884 | 0.965 / 1.153 | 0.780 / 0.967 | 0.992 / 1.153 |

Cambio de tiempo de `doctor` de ThinLTO frente a baseline, calculado a partir de las medianas emparejadas por ronda:

- tmpfs: -4.5 %, intervalo bootstrap 95 % [-6.0 %, -2.9 %].
- Btrfs: -4.0 %, intervalo bootstrap 95 % [-6.5 %, -1.3 %].

La reducción de CPU de `doctor` con ThinLTO es de aproximadamente 5.1 % en tmpfs y 4.6 % en Btrfs. Para `sync`, los intervalos de ambas series incluyen cero. `size_z` eleva la CPU de `doctor` aproximadamente 3.8 % y 2.5 %, respectivamente; su diferencia de tiempo en Btrfs es más incierta. Los valores completos de CPU, medias, p50, p95, p99 y los intervalos están en los JSON de resumen.

Los intervalos son descriptivos de estas rondas y este equipo, sin corrección por comparaciones múltiples. No son una garantía para otros procesadores. Las repeticiones independientes son la base para distinguir los efectos consistentes de las diferencias pequeñas de la primera serie.

## Método y alcance

- Equipo: Intel Core Ultra 7 255H, 16 núcleos lógicos, governor `powersave`, sesión de escritorio en uso. No se alteraron el governor ni los ajustes del sistema.
- Mismo código y lockfile para todas las compilaciones. Los perfiles se aplicaron mediante `CARGO_PROFILE_RELEASE_*`, en directorios de compilación separados; no se usó `target-cpu=native`, PGO ni UPX.
- Medición serial y caché caliente. Python y sus hijos se fijaron al núcleo lógico 0 durante las mediciones. Dentro de cada ronda se aleatorizó el orden de los pares variante/comando. No se ejecutaron builds ni las suites de regresión durante la toma de tiempos.
- Reloj `perf_counter_ns` alrededor de lanzamiento directo y espera del proceso, sin shell. CPU obtenida con `wait4`; para `report` incluye los descendientes esperados por el proceso. No se midió memoria ni arranque con caché fría.
- Ocho calentamientos por comando corto y dos para `report`. El reporte temporal se elimina fuera del intervalo medido antes de cada ejecución, porque la CLI rechaza sobrescribir un reporte existente.
- Primera serie: nueve variantes, 12 rondas × 25 muestras para cada uno de `help`, `sync`, `status`, `doctor --json`, y 12 × 2 para `report`. Confirmaciones: seis variantes y los cuatro comandos cortos. Total: **73,416 invocaciones medidas**, aparte de calentamientos y pruebas funcionales.
- Fixture aislado con dos perfiles, cargador, archivos propios de producción y un log sintético de puente sano. `doctor` tuvo cero fallos y cero advertencias antes de medir cada variante. No se usaron los perfiles reales ni se reescribió la paleta del escritorio.
- `report` consultó las herramientas externas reales; Omarchy 4.0.6 rechaza `omarchy --version`, salida que el reporte maneja como diagnóstico. El costo de esas consultas domina los ~420 ms y no mostró una mejora clara por perfil. Un piloto inicial con demasiadas repeticiones de `report` se detuvo y quedó excluido del conjunto publicado.
- Intervalos bootstrap: 5,000 remuestreos de los porcentajes de cambio de medianas emparejadas por ronda. Los percentiles de latencia usan interpolación lineal. Los intervalos de cambio no son el cociente de las medianas globales de la tabla.
- El puente JavaScript, inotify y el renderizado de Zen no fueron modificados. Este estudio mide la CLI; no permite afirmar que los cambios de tema completos o el navegador sean perceptiblemente más rápidos.

## Validación funcional

Las nueve variantes pasaron los 26 contratos de CLI: cinco de sincronización, trece de lectura/diagnóstico y ocho de estado. Las variantes strip, thin, fat1, size_s y size_z también pasaron la suite completa desechable de ciclo de vida y las regresiones JavaScript, incluyendo integridad de archivos contra SHA-256, instalación, reparación, conflictos, recuperación de actualización y desinstalación. Los logs se conservan junto al informe.

La sección `.text` de baseline y strip tiene el mismo SHA-256: `fa1a4ab7ab30eb3a6f5252ef862feb9ed0797781bcb71caf830879c84b96f4cc`. El ahorro de strip procede de símbolos, no de cambios a las instrucciones. Quitar símbolos reduce las posibilidades de diagnóstico mediante backtraces; conviene conservar el binario sin strip como artefacto de depuración si se adopta esta opción.

## Reproducción

Con Rust 1.99.1 y las dependencias descargadas (`cargo fetch --locked`), desde la raíz del repo:

```bash
python tests/release-profile-benchmark.py build --work /tmp/omazen-profiles-new --output /tmp/omazen-profiles-results
python tests/release-profile-benchmark.py contracts --work /tmp/omazen-profiles-new --output /tmp/omazen-profiles-results
python tests/release-profile-benchmark.py bench --work /tmp/omazen-profiles-new --output /tmp/omazen-profiles-results
python tests/release-profile-benchmark.py summarize --work /tmp/omazen-profiles-new --output /tmp/omazen-profiles-results
```

Para repetir la confirmación, añadir a `bench`:

```text
--variants baseline strip thin fat1 size_s size_z --scenarios help sync status doctor --rounds 30 --samples 60 --seed 20261031
```

Usar un directorio de salida distinto por serie. Para cambiar el filesystem del fixture manteniendo los ejecutables, crear otro directorio de trabajo y enlazar su subdirectorio `targets` al del primer trabajo; ejecutar allí solo `bench`. No ejecutar otra carga de pruebas simultáneamente.

## Datos conservados

- [Configuración, tamaño, tiempo de build y SHA-256 de binarios](builds.json).
- [Entorno y hashes de fuentes](environment.json).
- [Primera serie: muestras](samples.csv), [método](method.json), [resumen](summary.json).
- [Confirmación tmpfs: muestras](confirmation/samples.csv), [método](confirmation/method.json), [resumen](confirmation/summary.json).
- [Confirmación Btrfs: muestras](btrfs/samples.csv), [método](btrfs/method.json), [resumen](btrfs/summary.json).
