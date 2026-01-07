<?php
/**
 * Script de verificación de tabla wp_mpbm_inventory_log
 *
 * INSTRUCCIONES:
 * 1. Sube este archivo a: wp-content/plugins/my-pos-barcode-mobil-plugging/
 * 2. Accede vía navegador: https://tudominio.com/wp-content/plugins/my-pos-barcode-mobil-plugging/verificar_tabla.php
 * 3. Revisa el output
 */

// Cargar WordPress
require_once('../../../../wp-load.php');

// Solo permitir a administradores
if (!current_user_can('manage_options')) {
    die('Acceso denegado. Solo administradores.');
}

global $wpdb;
$table_name = $wpdb->prefix . 'mpbm_inventory_log';

echo "<h1>Verificación de Tabla de Inventario</h1>";
echo "<pre>";

// 1. Verificar si la tabla existe
echo "=== 1. VERIFICAR SI LA TABLA EXISTE ===\n";
$table_exists = $wpdb->get_var("SHOW TABLES LIKE '$table_name'");

if ($table_exists) {
    echo "✅ La tabla '$table_name' EXISTE\n\n";

    // 2. Mostrar estructura de la tabla
    echo "=== 2. ESTRUCTURA DE LA TABLA ===\n";
    $columns = $wpdb->get_results("DESCRIBE $table_name");
    foreach ($columns as $column) {
        echo sprintf("%-20s %-15s %s\n", $column->Field, $column->Type, $column->Null);
    }
    echo "\n";

    // 3. Contar registros totales
    echo "=== 3. ESTADÍSTICAS ===\n";
    $total_count = $wpdb->get_var("SELECT COUNT(*) FROM $table_name");
    echo "Total de registros: $total_count\n\n";

    // 4. Mostrar los últimos 10 movimientos
    echo "=== 4. ÚLTIMOS 10 MOVIMIENTOS ===\n";
    $recent_movements = $wpdb->get_results("
        SELECT movement_id, product_name, sku, quantity_changed,
               stock_before, stock_after, reason, log_date
        FROM $table_name
        ORDER BY log_date DESC
        LIMIT 10
    ");

    if ($recent_movements) {
        foreach ($recent_movements as $movement) {
            echo "Movement ID: {$movement->movement_id}\n";
            echo "  Producto: {$movement->product_name} (SKU: {$movement->sku})\n";
            echo "  Cantidad: {$movement->quantity_changed} (Stock: {$movement->stock_before} → {$movement->stock_after})\n";
            echo "  Razón: {$movement->reason}\n";
            echo "  Fecha: {$movement->log_date}\n";
            echo "  ---\n";
        }
    } else {
        echo "⚠️ NO HAY MOVIMIENTOS EN LA TABLA\n";
    }
    echo "\n";

    // 5. Buscar movimiento específico
    echo "=== 5. BUSCAR MOVIMIENTOS RECIENTES (últimas 2 horas) ===\n";
    $recent_time = date('Y-m-d H:i:s', strtotime('-2 hours'));
    $recent = $wpdb->get_results("
        SELECT movement_id, product_name, sku, log_date
        FROM $table_name
        WHERE log_date >= '$recent_time'
        ORDER BY log_date DESC
    ");

    if ($recent) {
        echo "Encontrados " . count($recent) . " movimientos en las últimas 2 horas:\n";
        foreach ($recent as $mov) {
            echo "  - {$mov->movement_id} | {$mov->product_name} ({$mov->sku}) | {$mov->log_date}\n";
        }
    } else {
        echo "❌ NO HAY MOVIMIENTOS EN LAS ÚLTIMAS 2 HORAS\n";
        echo "Esto confirma que los movimientos desde la app NO se están guardando.\n";
    }
    echo "\n";

    // 6. Verificar IDs específicos
    echo "=== 6. VERIFICAR MOVEMENT IDs ESPECÍFICOS ===\n";
    $test_ids = [
        '9c491521-82a8-4f0f-8d6f-939668187d03',
        '07ebbad2-6b43-4e98-88bb-205fc38c97f0',
        'dfad87b3-2987-47af-a7b4-b2b92841928f'
    ];

    foreach ($test_ids as $id) {
        $exists = $wpdb->get_var($wpdb->prepare(
            "SELECT COUNT(*) FROM $table_name WHERE movement_id = %s",
            $id
        ));
        $status = $exists > 0 ? "✅ EXISTE" : "❌ NO EXISTE";
        echo "$status - $id\n";
    }

} else {
    echo "❌ LA TABLA '$table_name' NO EXISTE\n";
    echo "\nLa tabla debe crearse cuando se activa el plugin.\n";
    echo "Intenta desactivar y reactivar el plugin MY POS BARCODE MOBIL.\n";
}

echo "</pre>";

// 7. Test de INSERT
echo "<h2>7. TEST DE INSERT</h2>";
echo "<pre>";

$test_insert = $wpdb->insert($table_name, [
    'movement_id' => 'TEST-' . wp_generate_uuid4(),
    'product_id' => 9999,
    'variation_id' => 0,
    'product_name' => 'PRODUCTO DE PRUEBA',
    'sku' => 'TEST-SKU',
    'quantity_changed' => 1,
    'stock_before' => 10,
    'stock_after' => 11,
    'reason' => 'test',
    'description' => 'Test de insert desde script de verificación',
    'user_id' => get_current_user_id(),
    'log_date' => current_time('mysql'),
]);

if ($test_insert) {
    $insert_id = $wpdb->insert_id;
    echo "✅ TEST INSERT EXITOSO\n";
    echo "   Insert ID: $insert_id\n";
    echo "   Esto significa que la tabla FUNCIONA correctamente.\n";

    // Limpiar el registro de prueba
    $wpdb->delete($table_name, ['id' => $insert_id]);
    echo "   (Registro de prueba eliminado)\n";
} else {
    echo "❌ TEST INSERT FALLÓ\n";
    echo "   Error: " . $wpdb->last_error . "\n";
    echo "   Esto indica un problema con los permisos o estructura de la tabla.\n";
}

echo "</pre>";

echo "<hr>";
echo "<p><strong>NOTA:</strong> Después de revisar, BORRA este archivo por seguridad.</p>";
?>
