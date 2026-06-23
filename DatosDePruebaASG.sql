-- =====================================================
-- Datos Iniciales: ProyectoASG
-- Motor: SQL Server
-- =====================================================

USE ProyectoASG;
GO

-- -----------------------------------------------------
-- Roles
-- -----------------------------------------------------
INSERT INTO rol (nombre_rol, descripcion) VALUES
('Administrador', 'Acceso total a la plataforma, gestión de usuarios y configuración del sistema'),
('Analista',      'Carga y gestión de indicadores ASG, generación de reportes y análisis de datos'),
('Consultor',     'Consulta de reportes, indicadores y recomendaciones sin capacidad de edición');
GO

-- -----------------------------------------------------
-- Usuarios
-- -----------------------------------------------------
INSERT INTO usuario (id_rol, nombre, correo, contrasena, estado) VALUES
(1, 'Carlos Mora Rodríguez',    'cmora@asganalytics.cr',       'hashed_pass_001', 'activo'),
(1, 'Daniela Ulate Brenes',     'dulate@asganalytics.cr',      'hashed_pass_002', 'activo'),
(2, 'Sofía Jiménez Vargas',     'sjimenez@asganalytics.cr',    'hashed_pass_003', 'activo'),
(2, 'Marco Araya Solano',       'maraya@asganalytics.cr',      'hashed_pass_004', 'activo'),
(2, 'Priscilla Núñez Castro',   'pnunez@asganalytics.cr',      'hashed_pass_005', 'activo'),
(3, 'Roberto Fallas Mora',      'rfallas@grupoice.cr',         'hashed_pass_006', 'activo'),
(3, 'Andrea Salas Quesada',     'asalas@bcr.fi.cr',            'hashed_pass_007', 'activo'),
(3, 'Esteban Chaves Pérez',     'echaves@coopelesca.cr',       'hashed_pass_008', 'activo'),
(3, 'Valeria Rojas Hernández',  'vrojas@florespalmares.cr',    'hashed_pass_009', 'activo'),
(3, 'Luis Montero Vindas',      'lmontero@dospinosflorex.cr',  'hashed_pass_010', 'activo');
GO

-- -----------------------------------------------------
-- Empresas (conocidas en Costa Rica)
-- -----------------------------------------------------
INSERT INTO empresa (id_usuario, nombre_empresa, cedula_juridica, sector, tamano, direccion, telefono) VALUES
(6,  'Instituto Costarricense de Electricidad (ICE)', '3-000-042139', 'Energía y Telecomunicaciones', 'Grande',  'La Sabana, San José',              '2220-7720'),
(7,  'Banco de Costa Rica (BCR)',                     '3-000-003085', 'Servicios Financieros',        'Grande',  'Av. 2, Calle 4-6, San José',       '2211-1111'),
(8,  'Coopelesca R.L.',                               '3-004-045231', 'Energía Eléctrica',            'Mediana', 'Ciudad Quesada, San Carlos',       '2401-8000'),
(9,  'Florex S.A. (Flores del Valle)',                '3-101-123456', 'Agricultura y Floricultura',   'Mediana', 'Palmares, Alajuela',               '2452-3000'),
(10, 'Dos Pinos R.L.',                                '3-004-045678', 'Agroindustria y Lácteos',      'Grande',  'La Valencia, Heredia',             '2293-8000');
GO

-- -----------------------------------------------------
-- Indicadores ASG
-- -----------------------------------------------------
INSERT INTO indicador (nombre_indicador, categoria, unidad_medida, descripcion) VALUES
-- Ambientales
('Emisiones de CO2',                  'Ambiental',  'toneladas',   'Emisiones anuales de dióxido de carbono generadas por operaciones'),
('Consumo energético total',          'Ambiental',  'kWh',         'Consumo total de energía eléctrica y térmica en el periodo'),
('Porcentaje de energía renovable',   'Ambiental',  'porcentaje',  'Proporción del consumo energético proveniente de fuentes renovables'),
('Consumo de agua',                   'Ambiental',  'metros3',     'Volumen total de agua utilizada en operaciones'),
('Residuos generados',                'Ambiental',  'toneladas',   'Total de residuos sólidos generados en el periodo'),
('Residuos reciclados',               'Ambiental',  'porcentaje',  'Porcentaje de residuos gestionados mediante reciclaje o reutilización'),
-- Sociales
('Empleados capacitados',             'Social',     'cantidad',    'Número de empleados que recibieron capacitación formal durante el año'),
('Horas de capacitación por empleado','Social',     'horas',       'Promedio de horas de formación recibidas por empleado'),
('Diversidad de género',              'Social',     'porcentaje',  'Porcentaje de mujeres dentro de la planilla total'),
('Índice de rotación de personal',    'Social',     'porcentaje',  'Porcentaje de empleados que dejaron la empresa en el periodo'),
('Accidentes laborales',              'Social',     'cantidad',    'Número de accidentes de trabajo registrados en el periodo'),
('Inversión social comunitaria',      'Social',     'CRC',         'Monto invertido en programas de responsabilidad social hacia la comunidad'),
-- Gobernanza
('Reuniones de junta directiva',      'Gobernanza', 'cantidad',    'Número de reuniones formales celebradas por la junta directiva'),
('Código de ética vigente',           'Gobernanza', 'sí/no',       'Indica si la empresa cuenta con un código de ética aprobado y publicado'),
('Denuncias por corrupción',          'Gobernanza', 'cantidad',    'Número de denuncias formales por conductas corruptas o antiéticas'),
('Políticas de privacidad de datos',  'Gobernanza', 'sí/no',       'Existencia de políticas formales para protección de datos personales'),
('Auditorías internas realizadas',    'Gobernanza', 'cantidad',    'Número de auditorías internas ejecutadas durante el periodo');
GO

-- -----------------------------------------------------
-- Registros de indicadores por empresa y periodo
-- -----------------------------------------------------
INSERT INTO registro_indicador (id_empresa, id_indicador, valor, periodo) VALUES
-- ICE (id_empresa = 1)
(1,  1,  12500.00, '2024-A'),  -- Emisiones CO2
(1,  2,  980000.00,'2024-A'),  -- Consumo energético
(1,  3,  87.50,    '2024-A'),  -- % energía renovable
(1,  7,  1850.00,  '2024-A'),  -- Empleados capacitados
(1,  9,  38.00,    '2024-A'),  -- Diversidad de género
(1,  13, 12.00,    '2024-A'),  -- Reuniones junta
(1,  14, 1.00,     '2024-A'),  -- Código de ética

-- BCR (id_empresa = 2)
(2,  1,  3200.00,  '2024-A'),
(2,  2,  410000.00,'2024-A'),
(2,  3,  55.00,    '2024-A'),
(2,  7,  2100.00,  '2024-A'),
(2,  9,  47.00,    '2024-A'),
(2,  13, 15.00,    '2024-A'),
(2,  14, 1.00,     '2024-A'),
(2,  16, 1.00,     '2024-A'),  -- Política de privacidad

-- Coopelesca (id_empresa = 3)
(3,  1,  870.00,   '2024-A'),
(3,  2,  125000.00,'2024-A'),
(3,  3,  92.00,    '2024-A'),
(3,  7,  340.00,   '2024-A'),
(3,  9,  33.00,    '2024-A'),
(3,  13, 10.00,    '2024-A'),
(3,  14, 1.00,     '2024-A'),

-- Florex (id_empresa = 4)
(4,  1,  420.00,   '2024-A'),
(4,  4,  18500.00, '2024-A'),  -- Consumo de agua
(4,  5,  95.00,    '2024-A'),  -- Residuos generados
(4,  6,  62.00,    '2024-A'),  -- % residuos reciclados
(4,  7,  180.00,   '2024-A'),
(4,  9,  58.00,    '2024-A'),
(4,  11, 2.00,     '2024-A'),  -- Accidentes laborales
(4,  12, 4500000.00,'2024-A'), -- Inversión social

-- Dos Pinos (id_empresa = 5)
(5,  1,  7800.00,  '2024-A'),
(5,  2,  530000.00,'2024-A'),
(5,  4,  95000.00, '2024-A'),
(5,  5,  310.00,   '2024-A'),
(5,  6,  71.00,    '2024-A'),
(5,  7,  1200.00,  '2024-A'),
(5,  9,  42.00,    '2024-A'),
(5,  12, 28000000.00,'2024-A'),
(5,  13, 13.00,    '2024-A'),
(5,  14, 1.00,     '2024-A'),
(5,  17, 4.00,     '2024-A');  -- Auditorías internas
GO

-- -----------------------------------------------------
-- Reportes
-- -----------------------------------------------------
INSERT INTO reporte (id_empresa, id_usuario, titulo, tipo_reporte, contenido) VALUES
(1, 3, 'Reporte ASG Anual 2024 - ICE',         'Anual',     'Análisis completo de indicadores ambientales, sociales y de gobernanza del ICE para el período 2024.'),
(2, 3, 'Reporte ASG Anual 2024 - BCR',         'Anual',     'Evaluación de desempeño ASG del Banco de Costa Rica con énfasis en inclusión financiera y gobernanza.'),
(3, 4, 'Reporte Ambiental 2024 - Coopelesca',  'Ambiental', 'Análisis del desempeño ambiental de Coopelesca con foco en energía renovable y huella de carbono.'),
(4, 4, 'Reporte Social 2024 - Florex',         'Social',    'Evaluación de indicadores sociales y gestión de residuos agrícolas en Florex S.A.'),
(5, 5, 'Reporte ASG Integral 2024 - Dos Pinos','Anual',     'Reporte integral de sostenibilidad de Dos Pinos R.L. incluyendo consumo hídrico, gestión de residuos e inversión comunitaria.');
GO

-- -----------------------------------------------------
-- Recomendaciones generadas por los reportes
-- -----------------------------------------------------
INSERT INTO recomendacion (id_reporte, descripcion, prioridad) VALUES
-- ICE
(1, 'Implementar un sistema de monitoreo en tiempo real de emisiones de CO2 en las plantas de generación térmica para identificar picos de contaminación y aplicar medidas correctivas inmediatas.', 'Alta'),
(1, 'Incrementar el porcentaje de mujeres en posiciones de jefatura, actualmente la diversidad de género en mandos medios está por debajo del promedio del sector energético nacional.', 'Media'),
-- BCR
(2, 'Formalizar una política de cero papel en sucursales mediante la digitalización de procesos de apertura de cuentas y gestión de créditos para reducir el consumo de recursos.', 'Media'),
(2, 'Reforzar los canales de denuncia anónima y actualizar el código de ética con lineamientos específicos sobre uso de datos personales de clientes.', 'Alta'),
-- Coopelesca
(3, 'Aprovechar la alta proporción de energía renovable para certificarse bajo estándares internacionales como ISO 14001, lo que abriría nuevos mercados y mejoraría la imagen corporativa.', 'Alta'),
(3, 'Diseñar un programa de capacitación en sostenibilidad dirigido a las comunidades abastecidas, fortaleciendo el componente social del modelo cooperativo.', 'Baja'),
-- Florex
(4, 'Reducir el consumo de agua mediante sistemas de riego por goteo y recolección de agua pluvial, ya que el sector agrícola representa uno de los mayores consumidores hídricos del país.', 'Alta'),
(4, 'Establecer alianzas con municipalidades locales para la correcta disposición de residuos de plaguicidas y empaques, actualmente gestionados sin un protocolo formal.', 'Alta'),
-- Dos Pinos
(5, 'Optimizar las rutas de recolección de leche para reducir emisiones de CO2 del transporte, que representa el mayor componente de la huella de carbono operativa.', 'Alta'),
(5, 'Incrementar la inversión en biogás a partir de residuos lácteos, una tecnología ya explorada por la cooperativa que puede reducir costos energéticos y emisiones simultáneamente.', 'Media');
GO