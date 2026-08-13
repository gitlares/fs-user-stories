# FS User Stories

## Plan integral de implementación

**Nombre público:** FS User Stories  
**Significado público:** Fast & Simple User Stories  
**Filosofía interna:** Fucking Simple User Stories  
**Licencia recomendada:** `MIT OR Apache-2.0`  
**Modelo:** local-first, sin cuenta obligatoria, sin servidor propio y con GitHub opcional únicamente para compartir proyectos.

---

## 1. Visión del producto

FS User Stories será una aplicación gráfica, nativa y multiplataforma para definir requisitos de software sin la complejidad de Jira u otras suites de gestión.

Permitirá:

- Crear proyectos locales.
- Definir los perfiles o roles que participan en cada proyecto.
- Crear historias de usuario.
- Escribir descripción, contexto y elementos fuera de alcance.
- Definir criterios de aceptación verificables.
- Adjuntar imágenes y archivos.
- Añadir comentarios.
- Asignar estados y prioridad.
- Trabajar completamente sin conexión.
- Compartir y sincronizar opcionalmente mediante un repositorio GitHub público o privado.
- Permitir que Codex, Claude y otros clientes compatibles lean y modifiquen historias mediante MCP.
- Exportar proyectos e historias a formatos abiertos.

### Propuesta de valor

> Escribe, organiza y comparte historias de usuario sin convertir el trabajo en una ceremonia de Jira.

### Principios no negociables

1. El guardado local nunca depende de internet.
2. La interfaz nunca queda bloqueada esperando una sincronización.
3. No se requiere una cuenta de FSUS.
4. GitHub es opcional y solamente transporta datos de FSUS.
5. Todo dato puede exportarse en formatos abiertos.
6. Ningún agente de IA obtiene permisos de escritura automáticamente.
7. No se incorporan funciones de gestión empresarial que desvirtúen la simplicidad.
8. Todo el código desarrollado por FSUS será open source.

---

## 2. Alcance y límites

### Incluido en la versión 1.0

- Proyectos.
- Perfiles funcionales del proyecto.
- Historias de usuario.
- Descripción enriquecida.
- Criterios de aceptación.
- Comentarios.
- Adjuntos.
- Estados configurables de forma limitada.
- Prioridad y etiquetas opcionales.
- Relaciones simples: relacionada, bloquea y bloqueada por.
- Historial de cambios.
- Sincronización opcional mediante GitHub.
- Resolución determinista de conflictos y asistente de resolución manual.
- MCP de lectura y escritura en escritorio.
- Exportación Markdown, JSON y ZIP.
- Importación de proyectos FSUS.
- Aplicaciones nativas para macOS, iOS/iPadOS, Windows y Linux.

### Excluido deliberadamente

- Sprints.
- Puntos de historia obligatorios.
- Registro de horas.
- Nómina o productividad individual.
- Presupuestos.
- CRM.
- Chat general.
- Videollamadas.
- Automatizaciones complejas.
- Workflows arbitrarios.
- Reportería ejecutiva avanzada.
- Servidor SaaS propio.
- Dependencia obligatoria de GitHub.

Si una función no ayuda directamente a definir, entender, compartir o implementar una historia, no entra en el núcleo del producto.

---

## 3. Plataformas y tecnología

### Interfaces nativas

| Plataforma | Tecnología de interfaz | Distribución inicial |
|---|---|---|
| macOS | SwiftUI y AppKit cuando sea necesario | DMG firmado y notarizado; posible Mac App Store |
| iOS/iPadOS | SwiftUI | App Store, aplicación pagada |
| Windows | WinUI 3 con C# | MSIX, GitHub Releases y posteriormente Microsoft Store |
| Linux | GTK 4 y libadwaita | Flatpak y paquete adicional según demanda |

### Núcleo compartido

Todo el dominio se implementará una sola vez en Rust:

```text
fsus-core
├── domain
├── storage
├── events
├── merge
├── sync
├── github
├── export
├── security
└── mcp
```

Las interfaces nativas se conectarán al núcleo mediante una ABI C estable:

- Swift llama al núcleo desde macOS/iOS.
- C# utiliza P/Invoke desde Windows.
- La aplicación GTK puede utilizar el núcleo directamente desde Rust.

Se evitará depender de runtimes incrustados. El usuario no instalará Git, Rust, Node ni Python.

### Dependencias base previstas

- Rust y Tokio para el núcleo asíncrono.
- SQLite para almacenamiento local.
- Serde para serialización.
- Reqwest o cliente HTTPS equivalente para GitHub.
- SDK MCP oficial de Rust o implementación compatible con licencia permisiva.
- Librería CRDT solamente si las pruebas demuestran que reduce complejidad real; no será una dependencia obligatoria desde el primer prototipo.

---

## 4. Arquitectura general

```text
┌──────────────────────────────────────────────────────────┐
│ Interfaces nativas                                       │
│ macOS · iOS/iPadOS · Windows · Linux                     │
└────────────────────────────┬─────────────────────────────┘
                             │ ABI estable
┌────────────────────────────▼─────────────────────────────┐
│ FSUS Core · Rust                                         │
│ comandos · consultas · validación · eventos · conflictos │
├───────────────┬─────────────────┬────────────────────────┤
│ SQLite local  │ GitHub opcional │ MCP de escritorio     │
└───────────────┴─────────────────┴────────────────────────┘
```

### Flujo de escritura

1. La interfaz envía un comando al núcleo.
2. El núcleo valida permisos y reglas.
3. Se abre una transacción SQLite.
4. Se crea un evento inmutable.
5. Se actualiza la proyección de lectura.
6. Se confirma la transacción.
7. La interfaz recibe éxito inmediatamente.
8. El sincronizador recibe una señal y trabaja en segundo plano.

GitHub nunca participa en los pasos necesarios para guardar localmente.

### Separación entre comandos y consultas

Las interfaces no modificarán SQLite directamente. Utilizarán operaciones del núcleo como:

```text
create_project
create_profile
create_story
update_story_description
add_acceptance_criterion
set_story_status
add_comment
attach_file
```

Las consultas serán independientes:

```text
list_projects
list_stories
get_story
search_stories
list_sync_conflicts
```

La interfaz gráfica y MCP utilizarán exactamente la misma capa de comandos. Esto evita comportamientos diferentes entre humanos y agentes.

---

## 5. Modelo de dominio

### Entidades principales

#### Project

- ID UUID/ULID.
- Nombre.
- Descripción opcional.
- Prefijo de historias, por ejemplo `NS`.
- Estados habilitados.
- Configuración de sincronización.
- Fecha de creación y modificación.

#### FunctionalProfile

Representa al actor funcional de una historia, no al colaborador que edita.

Ejemplos:

- Administrador.
- Gerente de desarrollo.
- Propietario de agencia.
- Asesor.
- Cliente.

Campos:

- ID estable.
- Nombre.
- Descripción.
- Color e icono opcionales.
- Estado activo/inactivo.

#### LocalIdentity

Identifica quién realizó un cambio:

- Persona: Daniel.
- Dispositivo: MacBook Pro de Daniel.
- Agente: Codex.
- Cliente MCP: Claude Code.

No es una cuenta remota. Se genera localmente y posee un ID estable por dispositivo.

#### Story

- ID interno estable.
- Referencia visible, por ejemplo `NS-142`.
- Título.
- Perfil funcional.
- Enunciado: como, quiero, para.
- Descripción estructurada por bloques.
- Fuera de alcance.
- Estado.
- Prioridad opcional.
- Etiquetas opcionales.
- Relaciones.
- Creador y fechas.
- Revisión causal actual.

#### AcceptanceCriterion

- ID estable independiente del texto.
- Texto.
- Orden.
- Estado: pendiente, verificado o no aplicable.
- Evidencia/comentario opcional.
- Autor y revisión.

#### Comment

- ID estable.
- Autor humano o agente.
- Contenido Markdown.
- Fecha.
- Referencia opcional a otro comentario.
- Versiones de edición.
- Tombstone si fue eliminado.

#### Attachment

- ID.
- Nombre original.
- MIME type.
- Tamaño.
- Hash criptográfico.
- Ruta interna basada en hash.
- Autor y fecha.
- Miniatura derivada cuando corresponda.

#### Event

- ID ULID.
- Proyecto y entidad.
- Dispositivo/actor.
- Tipo de operación.
- Datos del cambio.
- Revisión base conocida.
- reloj lógico/híbrido.
- Fecha local informativa.
- Hash de integridad.

#### Conflict

- Entidad y campos involucrados.
- Eventos causantes.
- Opciones disponibles.
- Recomendación determinista.
- Resolución elegida.
- Autor de la resolución.

### Estados predeterminados

```text
Borrador
Lista
En desarrollo
Revisión
Terminada
Descartada
```

El usuario podrá renombrarlos y cambiar colores, pero la primera versión no tendrá un diseñador arbitrario de workflows.

---

## 6. Persistencia local

### SQLite

- Modo WAL.
- Foreign keys activadas.
- Migraciones versionadas.
- Escrituras transaccionales.
- Índices para proyecto, estado, perfil y búsqueda.
- FTS5 para búsqueda local cuando esté disponible.
- Copias consistentes mediante SQLite Backup API.

### Estructura local

```text
FSUserStories/
├── fsus.sqlite3
├── attachments/
│   └── sha256/ab/cd/<hash>
├── exports/
├── logs/
└── backups/
```

Las credenciales nunca se guardarán dentro de la base:

- Keychain en Apple.
- Windows Credential Manager/DPAPI en Windows.
- Secret Service en Linux.

### Recuperación

- Journal de eventos como fuente reconstruible.
- Copia automática antes de cada migración.
- Exportación de proyecto a ZIP.
- Importación idempotente.
- Verificación de integridad al abrir la base.
- Opción de reconstruir proyecciones desde eventos.

---

## 7. Sincronización mediante GitHub

### Objetivo

GitHub solamente almacena eventos, objetos adjuntos y metadatos de FSUS. No recibe código fuente del proyecto de software ni acceso a otros repositorios.

Cada proyecto puede ser:

- Local únicamente.
- Compartido en repositorio privado.
- Compartido en repositorio público.

Privado será el valor recomendado y predeterminado.

### Permisos

Para repositorios privados o escritura se utilizará inicialmente un token fine-grained limitado al repositorio de FSUS con:

- Metadata: lectura.
- Contents: lectura/escritura.

No se solicitarán permisos para:

- Issues.
- Pull requests.
- Actions.
- Código de otros repositorios.
- Organizaciones completas.

### Protocolo de sincronización

La implementación inicial utilizará la API Git de GitHub por HTTPS, no un ejecutable Git.

Estructura remota:

```text
.fsus/
├── manifest.json
├── events/<device-id>/<event-id>.json
├── objects/<sha256>
├── snapshots/<snapshot-id>.json
└── schema-version
```

Los eventos y objetos son inmutables y utilizan rutas únicas. Para publicar:

1. Obtener el SHA actual de la referencia remota.
2. Crear blobs y árbol con los eventos pendientes.
3. Crear un commit cuyo padre sea el SHA observado.
4. Actualizar la referencia sin `force`.
5. Si otro dispositivo ganó la carrera, obtener el nuevo SHA y reintentar.

Como las rutas son únicas e inmutables, el reintento no pierde eventos ni necesita resolver conflictos textuales de Git.

### Máquina de estados del sincronizador

```text
Disabled
Idle
Debouncing
Fetching
Applying
Publishing
Backoff
NeedsAuthentication
NeedsUserResolution
```

### Comportamiento

- Debounce de cambios pequeños para reducir llamadas.
- Cola persistente.
- Reintentos exponenciales con jitter.
- Cancelación segura.
- Límites de concurrencia.
- Sincronización inmediata al recuperar internet.
- Sincronización al abrir y al volver al primer plano.
- Nunca bloquear comandos locales.

### iOS/iPadOS

iOS no garantiza ejecución continua. Se implementará:

- Sincronización inmediata en primer plano.
- Sincronización después de cada cambio si hay red.
- `BGAppRefreshTask` para trabajos breves concedidos por el sistema.
- `BGProcessingTask` cuando exista trabajo mayor y el sistema lo permita.
- Estado explícito: guardado localmente versus compartido.

No se prometerá sincronización instantánea cuando la aplicación esté suspendida.

### Compactación

Para evitar crecimiento ilimitado:

- Crear snapshots periódicos firmados por hash.
- Conservar eventos posteriores al snapshot.
- No borrar eventos remotos automáticamente en 1.0.
- Añadir compactación segura y verificable en una versión posterior.

---

## 8. Resolución de conflictos

### Principio

No utilizar “último escritor gana” salvo cuando existe una relación causal demostrable. La fecha de reloj del dispositivo no será autoridad suficiente.

### Metadatos causales

- Cada evento referencia la revisión que conocía.
- Cada entidad conserva el último evento por campo.
- Se utiliza reloj lógico/híbrido para ordenar sin confiar totalmente en la hora del sistema.
- Los eventos concurrentes se detectan como tales.

### Reglas automáticas

| Situación | Acción |
|---|---|
| Comentarios nuevos diferentes | Conservar ambos |
| Criterios nuevos diferentes | Conservar ambos |
| Adjuntos nuevos diferentes | Conservar todos |
| Campos diferentes de una historia | Combinar |
| Marcas sobre criterios diferentes | Combinar |
| Reordenamiento y edición de criterio diferente | Combinar por ID estable |
| Cambio posterior basado en el anterior | Conservar el posterior |
| Ediciones en bloques distintos | Fusionar por bloque |
| Ediciones concurrentes del mismo bloque | Crear conflicto visible |
| Eliminación versus edición | Conservar provisionalmente y preguntar |
| Estados concurrentes incompatibles | Preguntar |

### Asistente de resolución

La interfaz mostrará:

- Versión local.
- Versión remota.
- Diferencias resaltadas.
- Propuesta determinista cuando pueda generarse.
- Opción de conservar local, remota, ambas o editar resultado.
- Consecuencia de cada elección.

La resolución produce un nuevo evento que referencia explícitamente los eventos resueltos.

### IA opcional

Un LLM puede sugerir cómo combinar dos textos, pero:

- Nunca será necesario para sincronizar.
- Nunca resolverá silenciosamente.
- No enviará información a un proveedor sin autorización.
- La propuesta debe aprobarse manualmente.
- La versión determinista siempre estará disponible.

### Pruebas esenciales

Se crearán simulaciones de:

- Dos a cincuenta dispositivos.
- Relojes incorrectos.
- Eventos duplicados.
- Entrega desordenada.
- Cortes durante publicación.
- Reintentos repetidos.
- Edición y eliminación concurrentes.
- Restauración desde snapshot.

La propiedad principal será: aplicar el mismo conjunto de eventos en cualquier orden permitido produce el mismo estado final, salvo conflictos explícitos pendientes.

---

## 9. MCP y acceso para agentes

### Plataformas

| Plataforma | Soporte MCP |
|---|---|
| macOS | STDIO y Streamable HTTP local |
| Windows | STDIO y Streamable HTTP local |
| Linux | STDIO y Streamable HTTP local |
| iOS/iPadOS | Sin servidor persistente; App Intents, Share Sheet y exportación |

### Ejecutable

```text
fsus-mcp
```

Compartirá el mismo núcleo Rust. Podrá funcionar aunque la interfaz gráfica esté cerrada.

### Transportes

1. STDIO como opción recomendada para Codex y Claude Code.
2. Streamable HTTP opcional en `127.0.0.1`, nunca en `0.0.0.0` por defecto.

HTTP local requerirá:

- Token bearer generado localmente.
- Validación estricta de `Origin`.
- Puerto aleatorio o configurable.
- Rotación/revocación de token.
- Límites de tamaño y tiempo.

### Recursos MCP

```text
fsus://projects
fsus://projects/{project_id}
fsus://projects/{project_id}/profiles
fsus://projects/{project_id}/stories
fsus://projects/{project_id}/stories/{story_id}
fsus://projects/{project_id}/stories/{story_id}/attachments
```

### Herramientas de lectura

```text
list_projects
list_profiles
list_stories
get_story
search_stories
get_pending_stories
get_story_attachment
export_story_markdown
```

### Herramientas de escritura

```text
create_story
update_story
add_acceptance_criterion
update_acceptance_criterion
mark_acceptance_criterion
add_comment
set_story_status
attach_file
```

### Permisos

Los permisos se otorgan por cliente y proyecto:

```text
read_stories
read_attachments
create_stories
edit_stories
edit_criteria
add_comments
change_status
manage_attachments
```

Perfiles predeterminados:

- Solo lectura.
- Lectura y comentarios.
- Agente de desarrollo.
- Acceso completo.

Las escrituras estarán deshabilitadas por defecto. Cada cambio incluirá actor, cliente MCP y origen.

### Integración con Codex

La aplicación de escritorio podrá ofrecer “Conectar con Codex” y generar una configuración local equivalente a:

```toml
[mcp_servers.fs_user_stories]
command = "/ruta/a/fsus-mcp"
args = ["serve", "--stdio"]
enabled = true
default_tools_approval_mode = "writes"
```

La integración deberá respetar las opciones actuales de Codex para STDIO, Streamable HTTP, listas de herramientas y aprobación de escrituras.

### Auditoría

Toda operación de un agente se mostrará como actividad:

```text
NS-142 fue modificada por Codex
- Criterio 2 marcado como verificado.
- Comentario añadido.
- Estado cambiado a Revisión.
```

No se permitirá acceso directo de un agente a SQLite.

---

## 10. Experiencia de usuario

### Pantalla inicial

```text
FS User Stories

[Nuevo proyecto local]
[Abrir proyecto]
[Importar proyecto]
[Conectar proyecto con GitHub]
```

### Navegación principal

```text
Proyectos
└── Nuboo
    ├── Historias
    ├── Perfiles
    ├── Conflictos
    ├── Actividad
    └── Ajustes
```

### Editor de historia

Debe priorizar:

1. Título.
2. Perfil.
3. Como / quiero / para.
4. Descripción.
5. Criterios de aceptación.
6. Fuera de alcance.
7. Adjuntos.
8. Comentarios.

Estado, prioridad, etiquetas y relaciones estarán visibles pero sin dominar la pantalla.

### Objetivos de usabilidad

- Crear un proyecto en menos de un minuto.
- Crear una historia básica sin abrir configuración.
- Añadir criterios usando Enter.
- Adjuntar una imagen mediante arrastrar, pegar o selector nativo.
- Ver claramente si un cambio está guardado y si está compartido.
- Resolver un conflicto sin conocer Git.
- No mostrar commits, ramas o SHA en el flujo normal.

### Accesibilidad

- VoiceOver en Apple.
- Narrator/UI Automation en Windows.
- AT-SPI en Linux.
- Navegación completa por teclado.
- Contraste y tamaño dinámico.
- No depender únicamente del color para estados.

---

## 11. Licencias y propiedad intelectual

### Código

Licencia recomendada:

```text
MIT OR Apache-2.0
```

Cada archivo propio usará:

```text
SPDX-License-Identifier: MIT OR Apache-2.0
```

### Dependencias permitidas

```text
MIT
Apache-2.0
BSD-2-Clause
BSD-3-Clause
ISC
Zlib
0BSD
CC0-1.0
Public Domain
Unicode-3.0
```

### Dependencias condicionadas

- LGPL únicamente como dependencia dinámica de interfaz en Linux.
- OFL para fuentes.
- MPL 2.0 solamente después de revisión de aislamiento por archivo.

### Dependencias prohibidas dentro del núcleo/binarios Apple

```text
GPL
AGPL
SSPL
BSL
Commons Clause
Elastic License
PolyForm
Dependencias sin licencia verificable
```

### Controles

- `cargo-deny` en CI.
- Inventario automático de dependencias.
- `THIRD_PARTY_NOTICES.md` en cada versión.
- SBOM SPDX o CycloneDX.
- Revisión de licencias Swift, .NET y paquetes Linux.
- DCO y `Signed-off-by` para contribuciones.

### Marca

El código será libre, pero el nombre, logotipo e iconos oficiales podrán reservarse como marca. Los forks deberán poder usar el código sin presentarse como distribución oficial.

### Datos del usuario

Las historias, comentarios y adjuntos siguen siendo propiedad de sus autores. Usar FSUS no los coloca bajo MIT/Apache.

---

## 12. Seguridad y privacidad

### Superficie local

- Validar todas las rutas y nombres.
- Proteger contra path traversal.
- Sanitizar Markdown renderizado.
- Limitar tamaños de adjuntos configurables.
- Verificar MIME real además de extensión.
- No ejecutar adjuntos.
- Utilizar permisos restrictivos en archivos locales.

### Credenciales

- Almacén seguro de cada sistema operativo.
- Nunca incluir tokens en eventos, logs o exportaciones.
- Permitir revocación y desconexión.
- Enmascarar secretos en diagnósticos.

### GitHub

- Token fine-grained limitado al repositorio.
- Advertencia antes de convertir un proyecto en público.
- Confirmación adicional si existen adjuntos.
- TLS obligatorio.
- No usar `force push`.

### MCP

- Solo lectura por defecto.
- Permisos por proyecto.
- HTTP limitado a loopback.
- Token local.
- Validación de Origin.
- Auditoría de toda escritura.
- Límites de llamadas, tamaño y duración.
- Posibilidad de apagar completamente MCP.

### Cadena de suministro

- Dependencias bloqueadas mediante lockfiles.
- Auditoría de vulnerabilidades.
- Builds de release desde CI protegida.
- Firma y notarización.
- SBOM por versión.
- Publicación de checksums.

---

## 13. Estrategia de pruebas

### Núcleo

- Unit tests de cada agregado y regla.
- Property-based tests para eventos y merges.
- Pruebas de migraciones SQLite.
- Pruebas de reconstrucción completa.
- Fuzzing de importadores, eventos y Markdown.
- Pruebas de grandes volúmenes.

### Sincronización

- Servidor GitHub simulado.
- Respuestas 401, 403, 404, 409, 422, 429 y 5xx.
- Interrupciones y timeouts.
- Eventos duplicados y desordenados.
- Reintentos tras carrera de actualización de referencia.
- Repositorios públicos y privados.
- Adjuntos parciales.

### MCP

- Conformance tests del protocolo.
- STDIO y HTTP.
- Herramientas read-only y write.
- Matriz de permisos.
- Operaciones con la GUI cerrada.
- Integración real con Codex y Claude Code en pruebas de release.

### Interfaces

- Tests de view models/adapters.
- UI tests de flujos críticos.
- Accesibilidad automatizada y manual.
- Restauración después de cierre inesperado.
- Estados offline y autenticación vencida.

### Release gates

Ninguna versión estable se publica si:

- Existe pérdida de eventos conocida.
- Una migración no puede revertirse mediante backup.
- Hay una dependencia con licencia prohibida.
- MCP puede escribir sin autorización.
- El sincronizador bloquea la interfaz.
- No se puede exportar el proyecto completo.

---

## 14. CI/CD y distribución

### Repositorio principal

Monorepo para asegurar versiones compatibles del núcleo y las interfaces:

```text
fs-user-stories/
├── core/
├── mcp/
├── platforms/
│   ├── apple/
│   ├── windows/
│   └── linux/
├── schemas/
├── docs/
├── LICENSE-MIT
├── LICENSE-APACHE
└── THIRD_PARTY_NOTICES.md
```

### Pipeline

1. Formato y lint.
2. Tests Rust.
3. Tests de sincronización y conflictos.
4. Auditoría de seguridad y licencias.
5. Build macOS/iOS.
6. Build Windows.
7. Build Linux.
8. Tests MCP.
9. Generación de SBOM y avisos.
10. Firma y empaquetado en tags de release.

### Distribución

- GitHub Releases para fuentes y aplicaciones de escritorio.
- App Store para iOS/iPadOS.
- TestFlight para beta.
- MSIX y posteriormente Microsoft Store.
- Flatpak para Linux.

### Actualizaciones

- Aplicaciones fuera de tiendas: manifiesto firmado publicado en GitHub Releases.
- Aplicaciones de tienda: mecanismo de actualización de la tienda.
- Nunca descargar y ejecutar actualizaciones sin verificar firma.

---

## 15. Modelo comercial

### Escritorio

- Código abierto.
- Descarga gratuita oficial.
- Todas las funciones esenciales disponibles.
- Posible patrocinio, donaciones y soporte profesional.

### iOS/iPadOS

- Aplicación oficial pagada una sola vez.
- Precio inicial sugerido: USD 9.99–14.99.
- Sin anuncios.
- Sin suscripción obligatoria.
- Sin servidor propio.
- Sin telemetría invasiva.

El usuario paga por la distribución firmada, comodidad, actualizaciones y soporte oficial; no por una licencia exclusiva sobre el código.

### Marca

La marca FS User Stories permitirá diferenciar las compilaciones oficiales de forks legítimos.

---

## 16. Roadmap de implementación

Las duraciones son estimaciones de trabajo efectivo para un desarrollador con experiencia. Algunas fases pueden solaparse con un equipo.

### Fase 0 — Decisiones y prototipos técnicos

**Duración:** 2–3 semanas.

Entregables:

- ADR de arquitectura local-first.
- ADR de eventos y causalidad.
- ADR de ABI entre Rust y plataformas.
- ADR de sincronización GitHub mediante API.
- ADR de licencias.
- Spike Rust → Swift en macOS/iOS.
- Spike Rust → C# en Windows.
- Spike MCP STDIO.
- Simulación de publicación concurrente en GitHub.

Criterio de salida:

- Crear y leer una historia desde Rust, Swift y C#.
- Dos dispositivos simulados publican eventos concurrentes sin pérdida.
- Codex puede leer una historia mediante MCP experimental.

### Fase 1 — Núcleo local MVP

**Duración:** 4–6 semanas.

Entregables:

- Modelo de dominio.
- SQLite y migraciones.
- Event store.
- Proyecciones.
- Proyectos y perfiles.
- Historias.
- Criterios.
- Comentarios.
- Adjuntos.
- Estados.
- Exportación/importación.
- API ABI inicial.

Criterio de salida:

- Proyecto completo usable sin internet desde pruebas del núcleo.
- Reiniciar o cerrar durante una escritura no pierde ni corrompe datos.
- Exportar, borrar e importar produce el mismo contenido.

### Fase 2 — Aplicación macOS y MCP Alpha

**Duración:** 5–7 semanas.

Entregables:

- Navegación de proyectos.
- Lista y filtros de historias.
- Editor completo.
- Perfiles.
- Comentarios y adjuntos.
- Actividad.
- Copias y restauración.
- Accesibilidad básica.
- `fsus-mcp` mediante STDIO local.
- Herramientas MCP para leer y editar historias.
- Permisos de escritura por cliente y proyecto.
- Auditoría de operaciones realizadas por agentes.

Criterio de salida:

- Un usuario no técnico puede crear un proyecto y cinco historias sin documentación.
- Todas las funciones locales esenciales están disponibles gráficamente.
- Un agente autorizado puede leer y editar las mismas historias con la interfaz cerrada.
- Las escrituras de agentes requieren permiso explícito y quedan auditadas.

### Fase 3 — Sincronización GitHub Beta

**Duración:** 5–7 semanas.

Entregables:

- Configuración pública/privada.
- Token fine-grained.
- Cola persistente.
- Fetch/apply/publish.
- Backoff.
- Adjuntos.
- Indicadores de estado.
- Motor causal.
- UI de conflictos.
- Simulador multi-dispositivo.

Criterio de salida:

- Dos a diez dispositivos simulados convergen sin perder cambios.
- La aplicación continúa funcionando durante caída total de GitHub.
- Ningún conflicto se resuelve destructivamente en silencio.

### Fase 4 — Ampliación de MCP de escritorio

**Duración:** 3–4 semanas.

Entregables:

- Streamable HTTP local.
- Recursos.
- Ampliación y estabilización de herramientas.
- Administración avanzada de permisos por proyecto/cliente.
- Instalador/configurador para Codex.
- Guía para Claude Code.

Criterio de salida:

- Codex y Claude pueden leer una historia y sus adjuntos.
- Una escritura requiere permiso explícito y queda auditada.
- MCP funciona con la interfaz gráfica cerrada.

### Fase 5 — iOS/iPadOS

**Duración:** 5–7 semanas.

Entregables:

- Interfaz SwiftUI adaptativa.
- Editor móvil.
- Adjuntos desde cámara, fotos y archivos.
- Compartir/exportar.
- Sincronización foreground.
- BackgroundTasks.
- Keychain.
- App Intents y Atajos básicos.
- TestFlight.
- Preparación App Store.

Criterio de salida:

- Crear y editar offline en iPhone y sincronizar después.
- Nunca se presenta un cambio pendiente como compartido.
- La app pasa revisión interna de privacidad y licencias.

### Fase 6 — Windows

**Duración:** 4–6 semanas.

Entregables:

- WinUI 3.
- Integración ABI.
- Flujo funcional equivalente a macOS.
- Credential Manager.
- MCP.
- MSIX firmado.
- Accesibilidad.

Criterio de salida:

- Compatibilidad de proyecto y sincronización con Apple.
- Paquete instalable sin dependencias manuales.

### Fase 7 — Linux

**Duración:** 4–6 semanas.

Entregables:

- GTK 4/libadwaita.
- Secret Service.
- MCP.
- Flatpak.
- Integración con escritorio.
- Documentación de dependencias LGPL.

Criterio de salida:

- Compatibilidad de datos completa.
- Flatpak reproducible y permisos mínimos.

### Fase 8 — Estabilización 1.0

**Duración:** 3–5 semanas.

Entregables:

- Auditoría de datos y seguridad.
- Optimización.
- Accesibilidad completa.
- Traducciones iniciales ES/EN.
- Documentación.
- Sitio simple.
- SBOM y avisos.
- Firma de releases.
- Política de vulnerabilidades.
- App Store.

Criterio de salida:

- Cero defectos conocidos de pérdida de datos.
- Matriz multiplataforma aprobada.
- Importación/exportación validada.
- MCP y sincronización documentados.

---

## 17. Orden recomendado de lanzamiento

No se deben construir las cuatro interfaces simultáneamente desde el día uno.

1. Núcleo Rust y pruebas.
2. macOS como cliente de referencia con MCP local.
3. Sincronización GitHub.
4. Ampliación de MCP y Streamable HTTP.
5. iOS/iPadOS pagado.
6. Windows.
7. Linux.

macOS debe validar primero el producto porque comparte SwiftUI y gran parte de los adaptadores con iOS, pero permite desarrollar y depurar el MCP completo.

### Estimación realista

- Un desarrollador dedicado: aproximadamente 32–44 semanas para una 1.0 sólida en todas las plataformas.
- Equipo de tres personas —núcleo, Apple y Windows/Linux—: aproximadamente 18–24 semanas.
- Alpha local macOS con MCP y sin sincronización: 9–14 semanas después de cerrar prototipos.
- Primera versión vendible iOS después del núcleo, macOS y sync: alrededor de 18–25 semanas con un desarrollador dedicado.

Reducir estos tiempos implicaría disminuir plataformas o alcance, no eliminar pruebas de sincronización.

---

## 18. Backlog inicial por épicas

### EPIC-01 — Fundamentos y licencias

- Crear repositorio y licencias.
- Configurar DCO.
- Configurar auditoría de dependencias.
- Definir convenciones de IDs, eventos y schemas.
- Crear ADRs.

### EPIC-02 — Dominio

- Proyecto.
- Perfil funcional.
- Identidad local.
- Historia.
- Criterios.
- Comentarios.
- Adjuntos.
- Estados y relaciones.

### EPIC-03 — Persistencia

- SQLite WAL.
- Migraciones.
- Event store.
- Proyecciones.
- FTS.
- Backup y recuperación.

### EPIC-04 — Conflictos

- Reloj causal.
- Reglas por tipo de entidad.
- Conflict store.
- Resoluciones.
- Property tests.

### EPIC-05 — GitHub

- Credenciales.
- Repositorio público/privado.
- Descarga incremental.
- Publicación CAS/retry.
- Adjuntos.
- Backoff y observabilidad.

### EPIC-06 — MCP

- STDIO.
- HTTP local.
- Recursos.
- Herramientas.
- Permisos.
- Auditoría.
- Instalación en Codex/Claude.

### EPIC-07 — Apple

- macOS.
- iOS/iPadOS.
- Keychain.
- BackgroundTasks.
- Share Sheet/App Intents.
- Distribución.

### EPIC-08 — Windows

- WinUI.
- ABI.
- Credential Manager.
- MSIX.

### EPIC-09 — Linux

- GTK/libadwaita.
- Secret Service.
- Flatpak.

### EPIC-10 — Calidad y lanzamiento

- Accesibilidad.
- Seguridad.
- Traducciones.
- Documentación.
- SBOM.
- Firma.
- App Store.

---

## 19. Métricas técnicas y de producto

### Rendimiento

- Guardado local percibido: menos de 100 ms en operaciones comunes.
- MCP local de lectura: menos de 150 ms sin adjuntos grandes.
- Apertura de proyectos medianos: menos de un segundo en hardware objetivo.
- Ninguna operación de red en el hilo principal.

### Confiabilidad

- Cero pérdida de eventos en pruebas de caos.
- Importación/exportación determinista.
- Convergencia automática en ediciones no superpuestas.
- Conflictos visibles en toda edición realmente ambigua.

### Simplicidad

- Nueva historia en menos de sesenta segundos.
- Proyecto nuevo sin tutorial obligatorio.
- GitHub se configura una sola vez por proyecto.
- MCP de Codex se conecta desde un flujo guiado.

### Privacidad

- Cero telemetría obligatoria.
- Cero cuenta FSUS.
- Cero servidor FSUS.
- Cero permisos GitHub fuera del repositorio elegido.

---

## 20. Riesgos principales

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Mantener cuatro interfaces | Alto | Núcleo compartido, orden secuencial y paridad por contratos |
| Conflictos complejos de texto | Alto | Bloques con IDs, causalidad, pruebas y resolución explícita |
| Restricciones de fondo en iOS | Medio | Foreground sync, BackgroundTasks y estado honesto |
| UX de token GitHub | Medio | Asistente guiado; evaluar autenticación más cómoda sin ampliar permisos |
| Límites de API GitHub | Medio | Batching, debounce, caché, backoff y sync incremental |
| Crecimiento del event log | Medio | Snapshots y compactación posterior verificable |
| Dependencia accidental incompatible | Alto | `cargo-deny`, SBOM y release gate |
| MCP con demasiados permisos | Alto | Solo lectura por defecto, scopes y auditoría |
| Fork que use la misma identidad | Medio | Marca e iconos oficiales protegidos |
| Alcance creciendo hacia Jira | Alto | Principios no negociables y proceso explícito de rechazo |

---

## 21. Definición de terminado para la versión 1.0

FS User Stories 1.0 está terminado cuando:

- Funciona localmente sin cuenta ni internet.
- Los proyectos pueden exportarse e importarse completamente.
- macOS, iOS/iPadOS, Windows y Linux leen el mismo formato.
- GitHub público y privado sincronizan sin bloquear.
- Los cambios concurrentes no producen pérdida silenciosa.
- Codex y Claude pueden leer y, con permiso, modificar historias en escritorio.
- Toda acción de agentes queda auditada.
- Los secretos permanecen en el almacén seguro del sistema.
- No hay dependencias incompatibles con MIT/Apache.
- Los binarios están firmados o empaquetados según cada plataforma.
- La aplicación iOS está disponible como compra única.
- La documentación explica claramente la propiedad de datos y la marca.
- No existen defectos conocidos de corrupción o pérdida de información.

---

## 22. Primera acción recomendada

No comenzar por diseñar todas las pantallas. El primer ciclo debe construir un prototipo vertical que pruebe el riesgo real:

1. Crear una historia desde un comando Rust.
2. Guardarla como evento y proyección SQLite.
3. Mostrarla en una ventana SwiftUI de macOS.
4. Modificarla desde un MCP STDIO.
5. Publicar el evento en un repositorio GitHub de prueba.
6. Descargarlo desde una segunda instancia.
7. Crear una edición concurrente y resolverla sin pérdida.

Cuando ese recorrido funcione de extremo a extremo, la arquitectura estará validada. Después se amplían entidades y plataformas.

---

## Referencias técnicas

- OpenAI Docs: configuración MCP de Codex, transportes STDIO/Streamable HTTP y aprobación de herramientas: <https://learn.chatgpt.com/docs/extend/mcp?surface=cli>
- Especificación MCP: <https://modelcontextprotocol.io/specification/2026-07-28>
- SQLite y dominio público: <https://sqlite.org/copyright.html>
- Licencia de Swift: <https://www.swift.org/legal/license.html>
- Apple BackgroundTasks: <https://developer.apple.com/documentation/backgroundtasks>
- Apple Developer Program: <https://developer.apple.com/support/compare-memberships/>
- GitHub fine-grained repository permissions: <https://docs.github.com/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens>

---

**Estado del documento:** propuesta integral para validación antes de iniciar desarrollo.  
**Fecha:** 13 de agosto de 2026.
