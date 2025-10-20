<?php
/**
 * Se ejecuta al desinstalar el plugin.
 * Limpia las opciones de la base de datos.
 */

// Si no se está desinstalando desde WordPress, salir.
if (!defined('WP_UNINSTALL_PLUGIN')) {
    exit;
}

// Clave de la opción guardada en la base de datos.
$option_name = 'mypos_plugin_settings';

// Elimina la opción de la base de datos.
delete_option($option_name);
