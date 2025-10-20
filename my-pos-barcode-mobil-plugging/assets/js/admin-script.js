jQuery(document).ready(function ($) {
    function activateTab(tabHash) {
        if (!tabHash || $(tabHash).length === 0) {
            tabHash = $('.nav-tab-wrapper .nav-tab').first().attr('href');
        }
        $('.nav-tab-wrapper .nav-tab').removeClass('nav-tab-active');
        $('.mpbm-tab-content').hide();
        const activeTabLink = $('.nav-tab-wrapper .nav-tab[href="' + tabHash + '"]');
        activeTabLink.addClass('nav-tab-active');
        $(tabHash).show();
    }

    $('.nav-tab-wrapper .nav-tab').on('click', function(e) {
        e.preventDefault();
        const tabHash = $(this).attr('href');
        const cleanUrl = window.location.pathname + '?' + (window.location.search.split('?')[1] || '').split('&').filter(p => !p.startsWith('mpbm_')).join('&');
        if(history.pushState) {
            history.pushState(null, null, cleanUrl + tabHash);
        } else {
            window.location.hash = tabHash;
        }
        activateTab(tabHash);
    });

    let currentHash = window.location.hash;
    if (currentHash) {
        activateTab(currentHash);
    } else {
        activateTab($('.nav-tab-wrapper .nav-tab').first().attr('href'));
    }

    // --- LÓGICA DE IMPORTACIÓN CON AJAX ---
    $('#mpbm-import-form').on('submit', function(e) {
        e.preventDefault();
        
        const form = $(this);
        const feedbackDiv = $('#mpbm-import-feedback');
        const previewContainer = $('#mpbm-import-preview-container');
        const submitButton = form.find('button[type="submit"]');
        const fileInput = form.find('#mpbm_csv_file')[0];

        if (!fileInput.files || fileInput.files.length === 0) {
            feedbackDiv.html('<p class="notice notice-warning">Por favor, selecciona un archivo CSV para subir.</p>').show();
            return;
        }

        previewContainer.html('').hide();
        feedbackDiv.html('<p class="notice notice-info loading">Subiendo y procesando archivo...</p>').show();
        submitButton.prop('disabled', true);

        const formData = new FormData(this);
        formData.append('action', 'mpbm_preview_csv_import');

        $.ajax({
            url: mpbm_ajax_obj.ajax_url,
            type: 'POST',
            data: formData,
            processData: false,
            contentType: false,
            dataType: 'json',
            success: function(response) {
                if (response.success) {
                    feedbackDiv.html('').hide();
                    renderPreviewTable(response.data.products);
                } else {
                    const message = response.data && response.data.message ? response.data.message : 'Error desconocido al procesar el archivo.';
                    feedbackDiv.html('<p class="notice notice-error">' + message + '</p>');
                }
            },
            error: function(xhr) {
                let errorMsg = 'Error de comunicación con el servidor.';
                if (xhr.responseJSON && xhr.responseJSON.data && xhr.responseJSON.data.message) {
                    errorMsg = xhr.responseJSON.data.message;
                } else if (xhr.responseText) {
                    const match = xhr.responseText.match(/<b>Fatal error<\/b>:(.*?) in/);
                    if (match && match[1]) {
                        errorMsg = `Error fatal en el servidor: ${match[1].trim()}`;
                    }
                }
                feedbackDiv.html('<p class="notice notice-error">' + errorMsg + '</p>');
            },
            complete: function() {
                submitButton.prop('disabled', false);
                $('#mpbm_csv_file').val('');
            }
        });
    });

    function renderPreviewTable(products) {
        const previewContainer = $('#mpbm-import-preview-container');
        if (!products || products.length === 0) {
            previewContainer.html('<div class="mpbm-card"><p class="notice notice-warning">No se encontraron productos válidos para actualizar en el archivo.</p></div>').show();
            return;
        }

        let tableHtml = `
            <div class="mpbm-card">
                <h2>Previsualización de Ajuste de Stock</h2>
                <p>Se encontraron <strong>${products.length}</strong> productos en el CSV para actualizar. Revisa los cambios antes de confirmar.</p>
                <div class="mpbm-import-preview-list">
                    <table>
                        <thead>
                            <tr>
                                <th>SKU</th>
                                <th>Producto</th>
                                <th>Operación</th>
                                <th>Stock Actual</th>
                                <th>Nuevo Stock (Final)</th>
                                <th>Cambio</th>
                            </tr>
                        </thead>
                        <tbody>`;
        
        products.forEach(p => {
            const change = parseInt(p.change);
            const style = change > 0 ? 'color:green;' : (change < 0 ? 'color:red;' : '');
            const op_text = p.operation === 'add_stock' ? 'Añadir Stock' : 'Conteo Físico';
            tableHtml += `
                <tr>
                    <td>${escapeHtml(p.sku)}</td>
                    <td>${escapeHtml(p.name)}</td>
                    <td>${escapeHtml(op_text)}</td>
                    <td>${escapeHtml(p.old_stock)}</td>
                    <td><strong>${escapeHtml(p.new_stock)}</strong></td>
                    <td style="${style}">${change > 0 ? '+' : ''}${escapeHtml(change)}</td>
                </tr>`;
        });

        tableHtml += `
                        </tbody>
                    </table>
                </div>
                <form method="POST" action="${mpbm_ajax_obj.admin_post_url}">
                    <input type="hidden" name="action" value="mpbm_confirm_import">
                    <input type="hidden" name="mpbm_confirm_nonce" value="${mpbm_ajax_obj.confirm_nonce}">
                    <input type="hidden" name="mpbm_import_data" value='${escapeHtml(JSON.stringify(products))}'>
                    <p class="submit">
                        <button type="submit" class="button button-primary button-large">Confirmar y Aplicar Cambios</button>
                        <button type="button" class="button button-secondary" id="cancel-import-preview">Cancelar</button>
                    </p>
                </form>
            </div>`;

        previewContainer.html(tableHtml).show();
    }

    function escapeHtml(text) {
        if (text === null || text === undefined) return '';
        return String(text).replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m]));
    }

    $('#mpbm-import-preview-container').on('click', '#cancel-import-preview', function() {
        $('#mpbm-import-preview-container').html('').hide();
        $('#mpbm-import-feedback').html('').hide();
    });

    // --- LÓGICA DE HISTORIAL DE INVENTARIO (CON VISUALIZACIÓN MEJORADA) ---
    function loadInventoryHistory() {
        const container = $('#inventory-history-container');
        container.html('<p class="loading">Cargando historial...</p>');

        $.post(mpbm_ajax_obj.ajax_url, { action: 'mpbm_get_inventory_history', nonce: mpbm_ajax_obj.nonce })
            .done(function(response) {
                if (response.success && response.data.length > 0) {
                    let tableHtml = '<table class="wp-list-table widefat striped mpbm-history-table"><thead><tr><th>Fecha</th><th>Descripción del Movimiento</th><th>Cambio Total</th><th>Motivo</th><th>Usuario</th></tr></thead><tbody>';
                    
                    response.data.forEach(function(movement) {
                        let totalChange = 0;
                        movement.items.forEach(item => {
                            totalChange += parseInt(item.quantity_changed) || 0;
                        });

                        let productDetailsHtml = movement.items.map(item => {
                            const change = parseInt(item.quantity_changed) || 0;
                            const sign = change > 0 ? '+' : '';
                            const changeStyle = change > 0 ? 'color:green;' : 'color:red;';
                            return `
                                <li>
                                    <div class="product-name-sku">
                                        <span class="product-name">${escapeHtml(item.product_name)}</span>
                                        <span class="product-sku">SKU: ${escapeHtml(item.sku)}</span>
                                    </div>
                                    <div class="stock-details">
                                        <span class="stock-label">Antes:</span> <span class="stock-value">${escapeHtml(item.stock_before)}</span>
                                        <span class="stock-arrow">&rarr;</span>
                                        <span class="stock-label">Después:</span> <span class="stock-value">${escapeHtml(item.stock_after)}</span>
                                        <span class="stock-change" style="${changeStyle}"><strong>(${sign}${change})</strong></span>
                                    </div>
                                </li>`;
                        }).join('');

                        const totalChangeClass = totalChange > 0 ? 'color:green;' : (totalChange < 0 ? 'color:red;' : '');
                        const totalChangeValue = totalChange > 0 ? `+${totalChange}` : totalChange;

                        tableHtml += `
                            <tr class="mpbm-movement-row" data-movement-details-id="${escapeHtml(movement.movement_id)}">
                                <td style="white-space: nowrap;">${escapeHtml(movement.date)}</td>
                                <td>${escapeHtml(movement.description)} <span class="mpbm-toggle-details dashicons dashicons-arrow-down-alt2"></span></td>
                                <td style="${totalChangeClass} font-weight:bold;">${escapeHtml(totalChangeValue)} uds.</td>
                                <td style="text-transform: capitalize;">${escapeHtml(movement.reason)}</td>
                                <td>${escapeHtml(movement.user_name)}</td>
                            </tr>
                            <tr class="mpbm-movement-details-row" id="details-${escapeHtml(movement.movement_id)}">
                                <td colspan="5">
                                    <div class="mpbm-details-inner">
                                        <h4>Productos en este movimiento:</h4>
                                        <ul>${productDetailsHtml}</ul>
                                    </div>
                                </td>
                            </tr>`;
                    });

                    tableHtml += '</tbody></table>';
                    container.html(tableHtml);
                } else if (response.success) {
                    container.html('<p>No hay movimientos de inventario registrados.</p>');
                } else {
                    container.html('<p class="notice-error">Error: ' + (response.data || 'No se pudo cargar el historial.') + '</p>');
                }
            })
            .fail(function() {
                container.html('<p class="notice-error">Error de comunicación con el servidor.</p>');
            });
    }

    $('#inventory-history-container').on('click', '.mpbm-movement-row', function() {
        const detailsId = $(this).data('movement-details-id');
        const detailsRow = $('#details-' + detailsId);
        detailsRow.toggle(); // Simple toggle para mostrar/ocultar
        $(this).toggleClass('is-expanded');
    });

    // El resto del archivo JS permanece igual
    function renderDevicesList(devices) {
        const listContainer = $('#devices-list'); listContainer.empty();
        if (!devices || devices.length === 0) { listContainer.html('<p>No hay dispositivos vinculados.</p>'); return; }
        devices.forEach(device => { const deviceHtml = `<div class="device-item" data-id="${device.id}"><div><strong>${device.name}</strong> <small>(Vinculado: ${device.date})</small></div><button class="revoke-btn">Revocar</button></div>`; listContainer.append(deviceHtml); });
    }
    const initialDevices = JSON.parse($('#mpbm_devices_json').val() || '[]');
    renderDevicesList(initialDevices);
    $('#regenerate-api-key-btn').on('click', function() {
        if (!confirm('¿Estás seguro? Esto desconectará todos los dispositivos actuales.')) return;
        $.post(mpbm_ajax_obj.ajax_url, { action: 'mpbm_regenerate_api_key', nonce: mpbm_ajax_obj.nonce }, function(response) {
            if (response.success) { $('#api_key_field').val(response.data.new_key); renderDevicesList([]); alert('¡Nueva clave de API generada!'); }
        });
    });
    $('#copy-api-key-btn').on('click', function() {
        const apiKeyField = $('#api_key_field'); apiKeyField.select(); document.execCommand('copy'); $(this).text('¡Copiado!');
        setTimeout(() => $(this).text('Copiar'), 2000);
    });
    const qrContainer = document.getElementById('qr-code-container');
    $('#generate-qr-btn').on('click', function() {
        const deviceName = $('#device_name').val(); if (!deviceName) { alert('Por favor, introduce un nombre para el dispositivo.'); return; }
        const connectionData = { siteUrl: $('#mpbm_site_url').val(), apiKey: $('#api_key_field').val(), deviceName: deviceName };
        qrContainer.innerHTML = '';
        if (typeof QRCode !== 'undefined') { new QRCode(qrContainer, { text: JSON.stringify(connectionData), width: 200, height: 200 }); }
        $.post(mpbm_ajax_obj.ajax_url, { action: 'mpbm_link_device', nonce: mpbm_ajax_obj.nonce, device_name: deviceName }, function(response) {
            if (response.success) { renderDevicesList(response.data.devices); $('#device_name').val(''); }
        });
    });
    $('#devices-list').on('click', '.revoke-btn', function() {
        const deviceId = $(this).closest('.device-item').data('id');
        if (!confirm('¿Seguro que quieres revocar el acceso a este dispositivo?')) return;
        $.post(mpbm_ajax_obj.ajax_url, { action: 'mpbm_revoke_device', nonce: mpbm_ajax_obj.nonce, device_id: deviceId }, function(response) {
            if (response.success) { renderDevicesList(response.data.devices); }
        });
    });
    $('#prepare-export-btn').on('click', function() {
        const btn = $(this); const feedbackDiv = $('#export-feedback'); const downloadBtn = $('#download-export-btn');
        btn.prop('disabled', true).addClass('disabled').find('.dashicons').addClass('spin');
        downloadBtn.addClass('disabled').hide();
        feedbackDiv.html('<p class="loading">Recopilando productos, por favor espera...</p>').removeClass('notice-error notice-success').show();
        $.post(mpbm_ajax_obj.ajax_url, { action: 'mpbm_prepare_export', nonce: mpbm_ajax_obj.nonce })
            .done(function(response) {
                if (response.success) {
                    feedbackDiv.html(`<p class="notice-success">${response.data.count} productos listos para exportar.</p>`);
                    const downloadUrl = `${mpbm_ajax_obj.admin_post_url}?action=mpbm_export_inventory&nonce=${mpbm_ajax_obj.export_nonce}&key=${response.data.key}`;
                    downloadBtn.attr('href', downloadUrl).text(`Paso 2: Descargar ${response.data.count} Productos`).removeClass('disabled').show();
                } else {
                    feedbackDiv.html('<p class="notice-error">Error: ' + (response.data || 'No se pudieron recopilar los productos.') + '</p>');
                }
            })
            .fail(function() { feedbackDiv.html('<p class="notice-error">Error de comunicación con el servidor.</p>'); })
            .always(function() { btn.prop('disabled', false).removeClass('disabled').find('.dashicons').removeClass('spin'); });
    });
    function setupTool(tool) {
        const analyzeBtn = $(tool.analyzeBtn); const generationArea = $(tool.generationArea); const feedbackDiv = generationArea.find('.mpbm-feedback'); const productList = generationArea.find('.mpbm-product-list'); const confirmBtn = $(tool.confirmBtn); const checkbox = tool.checkbox ? $(tool.checkbox) : null;
        analyzeBtn.on('click', function() {
            const btn = $(this); btn.prop('disabled', true).addClass('disabled').find('.dashicons').addClass('spin');
            generationArea.slideUp(200, function() {
                productList.empty(); confirmBtn.hide();
                feedbackDiv.html('<p class="loading">Analizando productos, por favor espera...</p>').removeClass('notice-success notice-error').addClass('notice-warning').show();
                generationArea.slideDown(200);
            });
            const ajaxData = { action: tool.analyzeAction, nonce: mpbm_ajax_obj.nonce };
            if (checkbox) { ajaxData.regenerate_all = checkbox.is(':checked'); }
            $.post(mpbm_ajax_obj.ajax_url, ajaxData)
                .done(function(response) {
                    if (response.success && response.data.products.length > 0) {
                        feedbackDiv.html(`<p>Se encontraron ${response.data.products.length} productos para procesar.</p>`).removeClass('notice-warning').addClass('notice-success');
                        response.data.products.forEach(function(p) { const typeLabel = p.post_type === 'product_variation' ? ' <em>(Variación)</em>' : ''; productList.append(`<li>${p.post_title}${typeLabel} - (ID: ${p.ID})</li>`); });
                        confirmBtn.show();
                    } else if (response.success) {
                        feedbackDiv.html('<p>¡Excelente! No se encontraron productos que necesiten esta acción.</p>').removeClass('notice-warning').addClass('notice-success');
                    } else {
                        feedbackDiv.html('<p>Error: ' + (response.data || 'Error desconocido') + '</p>').removeClass('notice-warning').addClass('notice-error');
                    }
                })
                .fail(function() { feedbackDiv.html('<p>Error de comunicación con el servidor.</p>').removeClass('notice-warning').addClass('notice-error'); })
                .always(function() { btn.prop('disabled', false).removeClass('disabled').find('.dashicons').removeClass('spin'); });
        });
        confirmBtn.on('click', function() {
            const btn = $(this); if (!confirm(tool.confirmMessage)) return;
            btn.prop('disabled', true).addClass('disabled');
            feedbackDiv.html('<p class="loading">Procesando... Esto puede tardar unos momentos.</p>').removeClass('notice-success').addClass('notice-warning');
            const ajaxData = { action: tool.generateAction, nonce: mpbm_ajax_obj.nonce };
            if (checkbox) { ajaxData.regenerate_all = checkbox.is(':checked'); }
            $.post(mpbm_ajax_obj.ajax_url, ajaxData)
                .done(function(response) {
                    if (response.success) {
                        feedbackDiv.html('<p>' + response.data.message + '</p>').removeClass('notice-warning').addClass('notice-success');
                        productList.empty();
                        if (response.data.updated_products && response.data.updated_products.length > 0) {
                            productList.append('<h4>Resultados de la generación:</h4>');
                            response.data.updated_products.forEach(function(p) {
                                let resultHtml = '';
                                if (p.new_sku) { resultHtml = `<li><div class="product-info">${p.name}</div> <div class="product-code"><strong>SKU:</strong> ${p.new_sku}</div></li>`; } else if (p.new_barcode) { const barcodeType = $('#barcode_type').val(); resultHtml = `<li><div class="product-info">${p.name}</div> <div class="product-code"><strong>Código:</strong> ${p.new_barcode}</div> <div class="barcode-preview"><svg class="barcode" data-value="${p.new_barcode}" data-format="${barcodeType}"></svg></div></li>`; }
                                productList.append(resultHtml);
                            });
                            if (typeof JsBarcode === 'function') { $('.barcode').each(function() { const el = $(this); const value = el.data('value'); const format = el.data('format'); try { JsBarcode(this, value, { format: format, displayValue: false, margin: 0, width: 1.5, height: 40, font: "monospace", fontSize: 12 }); } catch (e) { $(this).parent().append('<span class="barcode-error">Inválido para ' + format + '</span>'); } }); }
                        }
                    } else { feedbackDiv.html('<p>Error: ' + (response.data || 'Error desconocido') + '</p>').removeClass('notice-warning').addClass('notice-error'); }
                })
                .fail(function() { feedbackDiv.html('<p>Error de comunicación con el servidor.</p>').removeClass('notice-warning').addClass('notice-error'); })
                .always(function() { btn.prop('disabled', false).removeClass('disabled').hide(); });
        });
    }
    setupTool({ analyzeBtn: '#analyze-skus-btn', generationArea: '#sku-generation-area', confirmBtn: '#generate-skus-confirm-btn', analyzeAction: 'mpbm_analyze_missing_skus', generateAction: 'mpbm_generate_missing_skus', confirmMessage: '¿Estás seguro? Esto generará SKUs para todos los productos listados.' });
    setupTool({ analyzeBtn: '#analyze-barcodes-btn', generationArea: '#barcode-generation-area', confirmBtn: '#generate-barcodes-confirm-btn', checkbox: '#regenerate-all-barcodes-checkbox', analyzeAction: 'mpbm_analyze_missing_barcodes', generateAction: 'mpbm_generate_barcodes_from_skus', confirmMessage: '¿Estás seguro? Esto generará/regenerará códigos de barras para todos los productos listados.' });
    
    $('a.nav-tab[href="#tab-historial-inventario"]').one('click', function() { loadInventoryHistory(); });
    if ($('.nav-tab-wrapper .nav-tab.nav-tab-active[href="#tab-historial-inventario"]').length) { loadInventoryHistory(); }
});