-- =====================================================
-- Modulo: Indicadores y Registro de Indicadores
-- Proyecto: ASG Analytics CR
-- Motor: SQL Server
-- =====================================================

USE ProyectoASG;
GO

-- =====================================================
-- SECCION 1: SCHEMA Y PERMISOS DEL MODULO
-- =====================================================

IF SCHEMA_ID('Indicadores') IS NULL
    EXEC('CREATE SCHEMA Indicadores');
GO

-- Le doy permisos al rol desarrollo sobre mi schema (solo si el
-- rol ya existe, es decir, si ya corrio el script compartido de
-- Avance_Kendall_Bitacora.sql).
IF DATABASE_PRINCIPAL_ID('desarrollo') IS NOT NULL
BEGIN
    GRANT EXECUTE ON SCHEMA::Indicadores TO desarrollo;
    GRANT SELECT  ON SCHEMA::Indicadores TO desarrollo;
END
GO


-- =====================================================
-- SECCION 2: PROCEDIMIENTOS ALMACENADOS - INDICADOR
-- =====================================================

-- Insertar indicador
CREATE OR ALTER PROCEDURE Indicadores.sp_InsertarIndicador
    @NombreIndicador VARCHAR(120),
    @Categoria       VARCHAR(30),
    @UnidadMedida    VARCHAR(30),
    @Descripcion     VARCHAR(255)
AS
BEGIN
    BEGIN TRY
        INSERT INTO indicador (nombre_indicador, categoria, unidad_medida, descripcion)
        VALUES (@NombreIndicador, @Categoria, @UnidadMedida, @Descripcion);
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo insertar el indicador. Se registro en la bitacora.';
    END CATCH
END
GO

-- Actualizar indicador
CREATE OR ALTER PROCEDURE Indicadores.sp_ActualizarIndicador
    @IdIndicador     INT,
    @NombreIndicador VARCHAR(120),
    @Categoria       VARCHAR(30),
    @UnidadMedida    VARCHAR(30),
    @Descripcion     VARCHAR(255)
AS
BEGIN
    BEGIN TRY
        UPDATE indicador
        SET nombre_indicador = @NombreIndicador,
            categoria        = @Categoria,
            unidad_medida    = @UnidadMedida,
            descripcion      = @Descripcion
        WHERE id_indicador = @IdIndicador;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo actualizar el indicador. Se registro en la bitacora.';
    END CATCH
END
GO

-- Eliminar indicador (el trigger trg_indicador_evitar_eliminar valida
-- que no tenga registros asociados; si falla, lo mando a la bitacora)
CREATE OR ALTER PROCEDURE Indicadores.sp_EliminarIndicador
    @IdIndicador INT
AS
BEGIN
    BEGIN TRY
        DELETE FROM indicador WHERE id_indicador = @IdIndicador;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo eliminar el indicador. Se registro en la bitacora.';
    END CATCH
END
GO

-- Listar indicadores
CREATE OR ALTER PROCEDURE Indicadores.sp_ListarIndicadores
AS
BEGIN
    SELECT id_indicador, nombre_indicador, categoria, unidad_medida, descripcion
    FROM indicador
    ORDER BY categoria, nombre_indicador;
END
GO

-- Listar indicadores filtrados por categoria (Ambiental, Social, Gobernanza)
CREATE OR ALTER PROCEDURE Indicadores.sp_ListarIndicadoresPorCategoria
    @Categoria VARCHAR(30)
AS
BEGIN
    SELECT id_indicador, nombre_indicador, categoria, unidad_medida, descripcion
    FROM indicador
    WHERE categoria = @Categoria
    ORDER BY nombre_indicador;
END
GO


-- =====================================================
-- SECCION 3: PROCEDIMIENTOS ALMACENADOS - REGISTRO_INDICADOR
-- =====================================================

-- Insertar registro de indicador para una empresa y periodo
CREATE OR ALTER PROCEDURE Indicadores.sp_InsertarRegistroIndicador
    @IdEmpresa   INT,
    @IdIndicador INT,
    @Valor       DECIMAL(12,2),
    @Periodo     VARCHAR(20)
AS
BEGIN
    BEGIN TRY
        INSERT INTO registro_indicador (id_empresa, id_indicador, valor, periodo)
        VALUES (@IdEmpresa, @IdIndicador, @Valor, @Periodo);
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo insertar el registro. Se registro en la bitacora.';
    END CATCH
END
GO

-- Actualizar registro de indicador
CREATE OR ALTER PROCEDURE Indicadores.sp_ActualizarRegistroIndicador
    @IdRegistro  INT,
    @Valor       DECIMAL(12,2),
    @Periodo     VARCHAR(20)
AS
BEGIN
    BEGIN TRY
        UPDATE registro_indicador
        SET valor   = @Valor,
            periodo = @Periodo
        WHERE id_registro = @IdRegistro;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo actualizar el registro. Se registro en la bitacora.';
    END CATCH
END
GO

-- Eliminar registro de indicador
CREATE OR ALTER PROCEDURE Indicadores.sp_EliminarRegistroIndicador
    @IdRegistro INT
AS
BEGIN
    BEGIN TRY
        DELETE FROM registro_indicador WHERE id_registro = @IdRegistro;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = NULL;
        PRINT 'No se pudo eliminar el registro. Se registro en la bitacora.';
    END CATCH
END
GO

-- Listar todos los registros de una empresa, con el nombre del indicador
CREATE OR ALTER PROCEDURE Indicadores.sp_ListarRegistrosPorEmpresa
    @IdEmpresa INT
AS
BEGIN
    SELECT r.id_registro, i.nombre_indicador, i.categoria, i.unidad_medida,
           r.valor, r.periodo, r.fecha_registro
    FROM registro_indicador r
    INNER JOIN indicador i ON r.id_indicador = i.id_indicador
    WHERE r.id_empresa = @IdEmpresa
    ORDER BY r.periodo DESC, i.categoria;
END
GO

-- Listar el historial de un indicador especifico para una empresa
-- (util para ver la evolucion del dato entre periodos)
CREATE OR ALTER PROCEDURE Indicadores.sp_HistorialIndicadorEmpresa
    @IdEmpresa   INT,
    @IdIndicador INT
AS
BEGIN
    SELECT r.periodo, r.valor, r.fecha_registro
    FROM registro_indicador r
    WHERE r.id_empresa = @IdEmpresa
      AND r.id_indicador = @IdIndicador
    ORDER BY r.periodo;
END
GO


-- =====================================================
-- SECCION 4: PROCEDIMIENTOS DE REPORTES Y ESTADISTICAS
-- =====================================================

-- Promedio de un indicador especifico entre todas las empresas
-- que lo hayan registrado en un periodo dado
CREATE OR ALTER PROCEDURE Indicadores.sp_PromedioIndicadorPorPeriodo
    @IdIndicador INT,
    @Periodo     VARCHAR(20)
AS
BEGIN
    SELECT i.nombre_indicador, @Periodo AS periodo,
           AVG(r.valor)   AS promedio,
           MIN(r.valor)   AS valor_minimo,
           MAX(r.valor)   AS valor_maximo,
           COUNT(*)       AS cantidad_empresas
    FROM registro_indicador r
    INNER JOIN indicador i ON r.id_indicador = i.id_indicador
    WHERE r.id_indicador = @IdIndicador
      AND r.periodo = @Periodo
    GROUP BY i.nombre_indicador;
END
GO

-- Totales y promedios por categoria (Ambiental/Social/Gobernanza)
-- para una empresa especifica
CREATE OR ALTER PROCEDURE Indicadores.sp_ResumenCategoriasPorEmpresa
    @IdEmpresa INT
AS
BEGIN
    SELECT i.categoria,
           COUNT(*)     AS cantidad_registros,
           AVG(r.valor) AS promedio_valor,
           SUM(r.valor) AS suma_valor
    FROM registro_indicador r
    INNER JOIN indicador i ON r.id_indicador = i.id_indicador
    WHERE r.id_empresa = @IdEmpresa
    GROUP BY i.categoria
    ORDER BY i.categoria;
END
GO

-- Cantidad de registros cargados por cada empresa (util para ver
-- que tan completa esta la informacion ASG de cada una)
CREATE OR ALTER PROCEDURE Indicadores.sp_CantidadRegistrosPorEmpresa
AS
BEGIN
    SELECT e.id_empresa, e.nombre_empresa,
           COUNT(r.id_registro) AS cantidad_registros
    FROM empresa e
    LEFT JOIN registro_indicador r ON r.id_empresa = e.id_empresa
    GROUP BY e.id_empresa, e.nombre_empresa
    ORDER BY cantidad_registros DESC;
END
GO

-- Ranking de empresas segun el valor que reportaron en un indicador
-- especifico y un periodo dado (por ejemplo, quien tiene mas
-- porcentaje de energia renovable)
CREATE OR ALTER PROCEDURE Indicadores.sp_RankingEmpresasPorIndicador
    @IdIndicador INT,
    @Periodo     VARCHAR(20)
AS
BEGIN
    SELECT e.nombre_empresa, i.nombre_indicador, r.valor, r.periodo
    FROM registro_indicador r
    INNER JOIN empresa e   ON r.id_empresa = e.id_empresa
    INNER JOIN indicador i ON r.id_indicador = i.id_indicador
    WHERE r.id_indicador = @IdIndicador
      AND r.periodo = @Periodo
    ORDER BY r.valor DESC;
END
GO


-- =====================================================
-- SECCION 5: TRIGGERS
-- =====================================================

-- Evita eliminar un indicador que ya tiene registros asociados
-- (mismo patron que trg_rol_evitar_eliminar de UsuarioYRoles.sql)
CREATE OR ALTER TRIGGER trg_indicador_evitar_eliminar
ON indicador
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM registro_indicador r
        INNER JOIN deleted d ON r.id_indicador = d.id_indicador
    )
    BEGIN
        RAISERROR('No se puede eliminar un indicador que ya tiene registros asociados.', 16, 1);
        RETURN;
    END

    DELETE FROM indicador
    WHERE id_indicador IN (SELECT id_indicador FROM deleted);
END
GO

-- Valida que el valor de un registro_indicador no sea negativo,
-- tanto al insertar como al actualizar
-- (mismo patron que trg_usuario_validar_correo de UsuarioYRoles.sql)
CREATE OR ALTER TRIGGER trg_registro_validar_valor
ON registro_indicador
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (SELECT 1 FROM inserted WHERE valor < 0)
    BEGIN
        RAISERROR('El valor del registro no puede ser negativo.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO


-- =====================================================
-- SECCION 6: PRUEBAS (ejecutar de arriba a abajo)
-- =====================================================

-- 1) Insertar un indicador de prueba
EXEC Indicadores.sp_InsertarIndicador
    @NombreIndicador = 'Huella hidrica por producto',
    @Categoria       = 'Ambiental',
    @UnidadMedida    = 'metros3',
    @Descripcion     = 'Consumo de agua por unidad de producto terminado';

-- 2) Listar indicadores y filtrar por categoria
EXEC Indicadores.sp_ListarIndicadores;
EXEC Indicadores.sp_ListarIndicadoresPorCategoria @Categoria = 'Ambiental';

-- 3) Insertar un registro de prueba para la empresa 1 (ICE)
--    (uso el id_indicador que salga del insertado arriba, aqui asumo 18)
-- EXEC Indicadores.sp_InsertarRegistroIndicador
--     @IdEmpresa = 1, @IdIndicador = 18, @Valor = 4200.00, @Periodo = '2024-A';

-- 4) Probar el trigger de valor negativo (esto DEBE dar error)
-- EXEC Indicadores.sp_InsertarRegistroIndicador
--     @IdEmpresa = 1, @IdIndicador = 18, @Valor = -50.00, @Periodo = '2024-A';

-- 5) Listar registros de una empresa y su historial
EXEC Indicadores.sp_ListarRegistrosPorEmpresa @IdEmpresa = 1;
EXEC Indicadores.sp_HistorialIndicadorEmpresa @IdEmpresa = 1, @IdIndicador = 1;

-- 6) Reportes y estadisticas
EXEC Indicadores.sp_PromedioIndicadorPorPeriodo @IdIndicador = 1, @Periodo = '2024-A';
EXEC Indicadores.sp_ResumenCategoriasPorEmpresa @IdEmpresa = 1;
EXEC Indicadores.sp_CantidadRegistrosPorEmpresa;
EXEC Indicadores.sp_RankingEmpresasPorIndicador @IdIndicador = 3, @Periodo = '2024-A';

-- 7) Probar el trigger de eliminar indicador con registros
--    (esto DEBE dar error porque el indicador 1 ya tiene registros)
-- EXEC Indicadores.sp_EliminarIndicador @IdIndicador = 1;