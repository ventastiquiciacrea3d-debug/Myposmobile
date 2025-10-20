=== MY POS BARCODE MOBIL Connector ===
Contributors: (Tu Nombre)
Tags: woocommerce, mobile, api, pos, barcode, scanner, inventory
Requires at least: 5.2
Tested up to: 6.4
Stable tag: 2.6.0
Requires PHP: 7.4
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Conecta la aplicación MY POS BARCODE MOBIL con WooCommerce, proveyendo una API de alto rendimiento, gestión de inventario y herramientas de productos.

== Description ==

Este plugin es el puente oficial entre tu tienda WooCommerce y la aplicación móvil "MY POS BARCODE MOBIL".
Proporciona las siguientes funcionalidades clave:

* **API REST Segura y de Alto Rendimiento:** Ofrece endpoints optimizados con consultas SQL directas y endpoints de lotes (`/batch`) para respuestas ultra rápidas, ideal para la app móvil en tiendas con grandes catálogos.
* **Gestión de Conexión Sencilla:** Una página de configuración intuitiva en el panel de WordPress para generar una clave de API y vincular dispositivos mediante un código QR.
* **Control de Dispositivos:** Lleva un registro de todos los dispositivos vinculados y permite revocar su acceso en cualquier momento.
* **Registro Detallado de Inventario:** Cada cambio de stock, ya sea desde la app o desde WordPress, se guarda en un historial detallado y consultable.
* **Herramientas de Importación y Exportación:** Exporta todo tu inventario a CSV para conteos físicos y vuelve a importar los ajustes masivamente.
* **Generadores de SKU y Códigos de Barras:** Herramientas para analizar y generar automáticamente SKUs o códigos de barras para productos que no los tengan.

== Installation ==

1.  Sube la carpeta `my-pos-barcode-mobil` al directorio `/wp-content/plugins/`.
2.  Activa el plugin a través del menú 'Plugins' en WordPress.
3.  Ve a la nueva página "POS Mobil App" en el menú de administración para configurar la conexión y usar las herramientas.

== Frequently Asked Questions ==

= ¿Necesito WooCommerce? =

Sí, este plugin está diseñado para funcionar exclusivamente con WooCommerce y no funcionará sin él.

= ¿Es segura la conexión? =

Sí. La comunicación entre la app y tu tienda está protegida por una clave de API única que tú controlas. Todas las peticiones desde la app móvil deben incluir esta clave.

== Changelog ==

= 2.6.0 =
* **MEJORA MAYOR DE RENDIMIENTO:** Refactorización completa de los endpoints de la API para usar consultas SQL directas, reduciendo drásticamente la carga del servidor.
* **NUEVO:** Endpoint de lotes (`/products/batch`) para obtener múltiples productos en una sola llamada.
* **NUEVO:** Endpoint para recibir y procesar ajustes de inventario masivos desde la app.
* **MEJORA:** La función de exportar a CSV ahora es más eficiente y soporta catálogos muy grandes.
* **MEJORA:** La interfaz del historial de inventario en el panel de admin ahora es expandible para una mejor visualización.