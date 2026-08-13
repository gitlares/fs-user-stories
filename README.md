# FS User Stories

**Fast & Simple User Stories**

FS User Stories es una aplicación local-first para crear y organizar historias de
usuario sin la complejidad de una suite de gestión de proyectos.

La idea es ofrecer una experiencia sencilla para documentar requisitos, criterios
de aceptación, comentarios y archivos adjuntos. Los datos se guardarán localmente
y podrán compartirse de forma opcional, sin requerir una cuenta propia del
servicio.

## Estado del proyecto

El proyecto se encuentra en etapa de planificación. Todavía no hay código de la
aplicación.

## Primera alpha

La primera versión alpha estará enfocada exclusivamente en macOS y funcionará de
forma local. Incluirá:

- Una interfaz nativa para crear y administrar historias de usuario.
- Un núcleo local encargado del dominio y la persistencia.
- Un servidor MCP para que agentes autorizados puedan leer y editar historias.
- Auditoría de los cambios realizados desde la aplicación o mediante MCP.

La sincronización remota y las demás plataformas no forman parte de esta alpha.

## Principios

- Funcionar sin conexión y sin una cuenta obligatoria.
- Mantener los datos bajo el control del usuario.
- Evitar procesos y funciones innecesarias.
- Utilizar formatos abiertos y portables.
- Mantener el proyecto como software de código abierto.
- Usar únicamente dependencias que permitan redistribución comercial.

## Documentación

La propuesta inicial se encuentra en
[`FS-User-Stories-Plan-de-Implementacion.md`](./FS-User-Stories-Plan-de-Implementacion.md).

## Licencia

El código de FS User Stories se distribuye bajo la [licencia MIT](./LICENSE).
Esta licencia permite distribuir versiones gratuitas o de pago, incluida la
aplicación oficial para iOS.
