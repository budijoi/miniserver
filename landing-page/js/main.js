// MiniServer Landing Page - Main JavaScript

let refreshInterval = 5;
let lastCPU = null;
let autoRefresh = true;
let refreshTimer = null;

document.addEventListener('DOMContentLoaded', function() {
    updateDateTime();
    startAutoRefresh();
    document.getElementById('lastUpdate').textContent = 'Memperbarui...';
});

function startAutoRefresh() {
    if (refreshTimer) clearInterval(refreshTimer);
    refreshTimer = setInterval(function() {
        if (autoRefresh) {
            refreshData();
        }
    }, refreshInterval * 1000);
}

async function refreshData() {
    try {
        const resp = await fetch('?ajax=1&_=' + Date.now());
        const data = await resp.json();
        updateDashboard(data);
        document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString('id-ID');
        document.getElementById('refreshStatus').innerHTML = '<i class="fas fa-sync-alt"></i>';
    } catch (err) {
        console.error('Refresh failed:', err);
        document.getElementById('refreshStatus').innerHTML = '<i class="fas fa-exclamation-triangle" style="color:#ef4444"></i>';
    }
}

function updateDashboard(data) {
    // CPU Temp
    const cpuTempEl = document.getElementById('cpuTemp');
    if (cpuTempEl) cpuTempEl.textContent = data.cpu_temp + '°C';

    // CPU Usage
    if (lastCPU && data.cpu) {
        const totalDiff = (data.cpu.user - lastCPU.user) + (data.cpu.nice - lastCPU.nice) +
            (data.cpu.system - lastCPU.system) + (data.cpu.idle - lastCPU.idle);
        const idleDiff = data.cpu.idle - lastCPU.idle;
        const usage = totalDiff > 0 ? Math.round((1 - idleDiff / totalDiff) * 100) : 0;

        const cpuUsageFill = document.getElementById('cpuUsageFill');
        const cpuUsageText = document.getElementById('cpuUsageText');
        if (cpuUsageFill) cpuUsageFill.style.width = usage + '%';
        if (cpuUsageText) cpuUsageText.textContent = usage + '%';
    }
    lastCPU = data.cpu;

    // RAM
    const ramUsed = document.getElementById('ramUsed');
    const ramAvail = document.getElementById('ramAvail');
    const ramUsageFill = document.getElementById('ramUsageFill');
    const ramUsageText = document.getElementById('ramUsageText');

    if (ramUsed) ramUsed.textContent = formatBytes(data.ram.used * 1024);
    if (ramAvail) ramAvail.textContent = formatBytes(data.ram.available * 1024);
    if (ramUsageFill) ramUsageFill.style.width = data.ram.percent + '%';
    if (ramUsageText) ramUsageText.textContent = data.ram.percent + '%';

    // Storage
    if (data.storage) {
        for (const [label, st] of Object.entries(data.storage)) {
            const usedEl = document.getElementById('storageUsed_' + label);
            const freeEl = document.getElementById('storageFree_' + label);
            const pctEl = document.getElementById('storagePercent_' + label);
            const fillEl = document.querySelector('.storage-fill');

            if (usedEl) usedEl.textContent = formatBytes(st.used);
            if (freeEl) freeEl.textContent = formatBytes(st.free);
            if (pctEl) pctEl.textContent = st.percent + '%';
        }
    }

    // SWAP
    const swapUsed = document.getElementById('swapUsed');
    const swapPercent = document.getElementById('swapPercent');
    const swapFill = document.querySelector('.swap-fill');

    if (swapUsed) swapUsed.textContent = formatBytes(data.swap.used * 1024);
    if (swapPercent) swapPercent.textContent = data.swap.percent + '%';
    if (swapFill) swapFill.style.width = data.swap.percent + '%';

    // ZRAM
    const zramUsed = document.getElementById('zramUsed');
    const zramPercent = document.getElementById('zramPercent');
    const zramFill = document.querySelector('.zram-fill');

    if (zramUsed) zramUsed.textContent = formatBytes(data.zram.used);
    if (zramPercent) zramPercent.textContent = data.zram.percent + '%';
    if (zramFill) zramFill.style.width = data.zram.percent + '%';

    // Network
    const totalRX = document.getElementById('totalRX');
    const totalTX = document.getElementById('totalTX');

    if (totalRX) totalRX.textContent = formatBytes(data.network.total_rx);
    if (totalTX) totalTX.textContent = formatBytes(data.network.total_tx);
}

function formatBytes(bytes, precision) {
    if (precision === undefined) precision = 2;
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), units.length - 1);
    return parseFloat((bytes / Math.pow(k, i)).toFixed(precision)) + ' ' + units[i];
}

function changeTheme(theme) {
    const d = new Date();
    d.setTime(d.getTime() + (365 * 24 * 60 * 60 * 1000));
    document.cookie = 'theme=' + theme + ';expires=' + d.toUTCString() + ';path=/';
    window.location.reload();
}

function updateDateTime() {
    const now = new Date();
    const dateEl = document.getElementById('currentDate');
    const timeEl = document.getElementById('currentTime');
    if (dateEl) dateEl.textContent = now.toLocaleDateString('id-ID', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    if (timeEl) timeEl.textContent = now.toLocaleTimeString('id-ID');
}

async function serviceAction(service, action) {
    const modal = document.getElementById('serviceModal');
    const modalTitle = document.getElementById('modalTitle');
    const modalOutput = document.getElementById('modalOutput');

    modalTitle.textContent = service + ' - ' + action;
    modalOutput.textContent = 'Menjalankan ' + action + ' pada ' + service + '...\n';
    modal.style.display = 'flex';

    try {
        const resp = await fetch(window.location.href.split('?')[0].replace(/\/+$/, '') + '/api.php', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'service=' + encodeURIComponent(service) + '&action=' + encodeURIComponent(action)
        });
        const result = await resp.text();
        modalOutput.textContent += result;

        // Refresh services grid after 2 seconds
        setTimeout(function() {
            location.reload();
        }, 2000);
    } catch (err) {
        modalOutput.textContent += '\nError: ' + err.message;
    }
}

function closeModal() {
    document.getElementById('serviceModal').style.display = 'none';
}

window.addEventListener('click', function(event) {
    const modal = document.getElementById('serviceModal');
    if (event.target === modal) {
        modal.style.display = 'none';
    }
});
