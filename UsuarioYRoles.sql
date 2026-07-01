
USE ProyectoASG;
GO

-- SECCION 1: SCHEMA Y PERMISOS DEL MODULO

IF SCHEMA_ID('Seguridad') IS NULL
    EXEC('CREATE SCHEMA Seguridad');
GO

-- Le doy permisos al rol desarrollo sobre mi schema (solo si el
-- rol ya existe, es decir, si ya corrio el script compartido).
IF DATABASE_PRINCIPAL_ID('desarrollo') IS NOT NULL
BEGIN
    GRANT EXECUTE ON SCHEMA::Seguridad TO desarrollo;
    GRANT SELECT  ON SCHEMA::Seguridad TO desarrollo;
END
GO


-- SECCION 2: PROCEDIMIENTOS ALMACENADOS - ROL

-- Insertar rol
CREATE OR ALTER PROCEDURE Seguridad.sp_InsertarRol
    @NombreRol   VARCHAR(50),
    @Descripcion VARCHAR(200)
AS
BEGIN
    INSERT INTO rol (nombre_rol, descripcion)
    VALUES (@NombreRol, @Descripcion);
END
GO

-- Actualizar rol
CREATE OR ALTER PROCEDURE Seguridad.sp_ActualizarRol
    @IdRol       INT,
    @NombreRol   VARCHAR(50),
    @Descripcion VARCHAR(200)
AS
BEGIN
    UPDATE rol
    SET nombre_rol  = @NombreRol,
        descripcion = @Descripcion
    WHERE id_rol = @IdRol;
END
GO

-- Eliminar rol (el trigger trg_rol_evitar_eliminar valida que
-- no tenga usuarios asignados; si falla, lo mando a la bitacora)
CREATE OR ALTER PROCEDURE Seguridad.sp_EliminarRol
    @IdRol INT
AS
BEGIN
    BEGIN TRY
        DELETE FROM rol WHERE id_rol = @IdRol;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo eliminar el rol. Se registro en la bitacora.';
    END CATCH
END
GO

-- Listar roles
CREATE OR ALTER PROCEDURE Seguridad.sp_ListarRoles
AS
BEGIN
    SELECT id_rol, nombre_rol, descripcion
    FROM rol
    ORDER BY id_rol;
END
GO


-- SECCION 3: PROCEDIMIENTOS ALMACENADOS - USUARIO

-- Insertar usuario. La contrasena se guarda cifrada con
-- HASHBYTES (SHA2_256) convertida a texto hexadecimal.
CREATE OR ALTER PROCEDURE Seguridad.sp_InsertarUsuario
    @IdRol      INT,
    @Nombre     VARCHAR(100),
    @Correo     VARCHAR(100),
    @Contrasena VARCHAR(255)
AS
BEGIN
    BEGIN TRY
        INSERT INTO usuario (id_rol, nombre, correo, contrasena, estado)
        VALUES (
            @IdRol,
            @Nombre,
            @Correo,
            CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', @Contrasena), 2),
            'activo'
        );
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo insertar el usuario. Se registro en la bitacora.';
    END CATCH
END
GO

-- Actualizar datos basicos del usuario (no toca la contrasena)
CREATE OR ALTER PROCEDURE Seguridad.sp_ActualizarUsuario
    @IdUsuario INT,
    @IdRol     INT,
    @Nombre    VARCHAR(100),
    @Correo    VARCHAR(100)
AS
BEGIN
    UPDATE usuario
    SET id_rol = @IdRol,
        nombre = @Nombre,
        correo = @Correo
    WHERE id_usuario = @IdUsuario;
END
GO

-- Cambiar estado del usuario (activo / inactivo)
CREATE OR ALTER PROCEDURE Seguridad.sp_CambiarEstadoUsuario
    @IdUsuario INT,
    @Estado    VARCHAR(20)
AS
BEGIN
    IF @Estado NOT IN ('activo', 'inactivo')
    BEGIN
        RAISERROR('El estado debe ser activo o inactivo.', 16, 1);
        RETURN;
    END

    UPDATE usuario
    SET estado = @Estado
    WHERE id_usuario = @IdUsuario;
END
GO

-- Eliminar usuario
CREATE OR ALTER PROCEDURE Seguridad.sp_EliminarUsuario
    @IdUsuario INT
AS
BEGIN
    BEGIN TRY
        DELETE FROM usuario WHERE id_usuario = @IdUsuario;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = @IdUsuario;
        PRINT 'No se pudo eliminar el usuario. Se registro en la bitacora.';
    END CATCH
END
GO

-- Listar usuarios con el nombre del rol
CREATE OR ALTER PROCEDURE Seguridad.sp_ListarUsuarios
AS
BEGIN
    SELECT u.id_usuario, u.nombre, u.correo, r.nombre_rol,
           u.estado, u.fecha_registro
    FROM usuario u
    INNER JOIN rol r ON u.id_rol = r.id_rol
    ORDER BY u.id_usuario;
END
GO

-- Autenticar: devuelve los datos del usuario si el correo y la
-- contrasena coinciden y esta activo; si no, no devuelve filas.
CREATE OR ALTER PROCEDURE Seguridad.sp_AutenticarUsuario
    @Correo     VARCHAR(100),
    @Contrasena VARCHAR(255)
AS
BEGIN
    SELECT u.id_usuario, u.nombre, u.correo, r.nombre_rol
    FROM usuario u
    INNER JOIN rol r ON u.id_rol = r.id_rol
    WHERE u.correo = @Correo
      AND u.contrasena = CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', @Contrasena), 2)
      AND u.estado = 'activo';
END
GO

-- Resumen: cantidad de usuarios por rol (consulta agrupada)
CREATE OR ALTER PROCEDURE Seguridad.sp_ResumenUsuariosPorRol
AS
BEGIN
    SELECT r.nombre_rol,
           COUNT(u.id_usuario) AS cantidad_usuarios
    FROM rol r
    LEFT JOIN usuario u ON u.id_rol = r.id_rol
    GROUP BY r.nombre_rol
    ORDER BY cantidad_usuarios DESC;
END
GO


-- SECCION 4: FUNCIONES

-- Cuenta cuantos usuarios tiene un rol
CREATE OR ALTER FUNCTION Seguridad.fn_ContarUsuariosPorRol(@IdRol INT)
RETURNS INT
AS
BEGIN
    DECLARE @Total INT;
    SELECT @Total = COUNT(*)
    FROM usuario
    WHERE id_rol = @IdRol;
    RETURN ISNULL(@Total, 0);
END
GO

-- Valida credenciales y devuelve el id del usuario (0 si no coincide)
CREATE OR ALTER FUNCTION Seguridad.fn_ValidarCredenciales
(
    @Correo     VARCHAR(100),
    @Contrasena VARCHAR(255)
)
RETURNS INT
AS
BEGIN
    DECLARE @Id INT = 0;
    SELECT @Id = id_usuario
    FROM usuario
    WHERE correo = @Correo
      AND contrasena = CONVERT(VARCHAR(255), HASHBYTES('SHA2_256', @Contrasena), 2)
      AND estado = 'activo';
    RETURN ISNULL(@Id, 0);
END
GO


-- SECCION 5: VISTAS

-- Usuarios con el rol legible (sin mostrar la contrasena)
CREATE OR ALTER VIEW Seguridad.vista_usuarios_detalle
AS
SELECT u.id_usuario,
       u.nombre,
       u.correo,
       r.nombre_rol,
       u.estado,
       u.fecha_registro
FROM usuario u
INNER JOIN rol r ON u.id_rol = r.id_rol;
GO

-- Solo los usuarios activos
CREATE OR ALTER VIEW Seguridad.vista_usuarios_activos
AS
SELECT id_usuario, nombre, correo, id_rol, fecha_registro
FROM usuario
WHERE estado = 'activo';
GO


-- SECCION 6: TRIGGERS

-- Evita eliminar un rol que todavia tiene usuarios asignados
CREATE OR ALTER TRIGGER trg_rol_evitar_eliminar
ON rol
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN deleted d ON u.id_rol = d.id_rol
    )
    BEGIN
        RAISERROR('No se puede eliminar un rol con usuarios asignados.', 16, 1);
        RETURN;
    END

    DELETE FROM rol
    WHERE id_rol IN (SELECT id_rol FROM deleted);
END
GO

-- Valida el formato del correo al insertar o actualizar usuarios
CREATE OR ALTER TRIGGER trg_usuario_validar_correo
ON usuario
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (SELECT 1 FROM inserted WHERE correo NOT LIKE '%_@_%.__%')
    BEGIN
        RAISERROR('El correo no tiene un formato valido.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO


-- SECCION 7: PRUEBAS (ejecutar de arriba a abajo)

-- 1) Insertar un usuario de prueba (la contrasena se cifra sola)
EXEC Seguridad.sp_InsertarUsuario
    @IdRol = 2,
    @Nombre = 'Jenny Fung Lin',
    @Correo = 'jenny.fung@asganalytics.cr',
    @Contrasena = 'clave123';

-- 2) Listar usuarios y ver la vista
EXEC Seguridad.sp_ListarUsuarios;
SELECT * FROM Seguridad.vista_usuarios_detalle;

-- 3) Cambiar estado y ver solo los activos
--    (uso el id que salga del usuario recien creado)
-- EXEC Seguridad.sp_CambiarEstadoUsuario @IdUsuario = 11, @Estado = 'inactivo';
SELECT * FROM Seguridad.vista_usuarios_activos;

-- 4) Probar las funciones
SELECT Seguridad.fn_ContarUsuariosPorRol(2) AS usuarios_analista;
SELECT Seguridad.fn_ValidarCredenciales('jenny.fung@asganalytics.cr', 'clave123') AS id_login;

-- 5) Probar autenticacion (debe devolver la fila del usuario)
EXEC Seguridad.sp_AutenticarUsuario 'jenny.fung@asganalytics.cr', 'clave123';

-- 6) Resumen de usuarios por rol
EXEC Seguridad.sp_ResumenUsuariosPorRol;

-- 7) Probar el trigger (esto DEBE dar error porque el rol 3 tiene usuarios)
-- EXEC Seguridad.sp_EliminarRol @IdRol = 3;