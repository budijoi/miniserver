<?php
session_start();

// Konfigurasi
$config = [
    'site_name' => 'MiniServer',
    'theme' => $_COOKIE['theme'] ?? 'modern',
    'refresh_interval' => 5, // detik
    'admin_email' => 'admin@localhost',
];

// Ambil data sistem
function getSystemInfo() {
    $info = [];

    // CPU
    $cpuRaw = @file_get_contents('/proc/stat');
    if ($cpuRaw) {
        $cpuLine = explode("\n", $cpuRaw)[0];
        $cpuData = preg_split('/\s+/', $cpuLine);
        $info['cpu'] = [
            'user' => $cpuData[1] ?? 0,
            'nice' => $cpuData[2] ?? 0,
            'system' => $cpuData[3] ?? 0,
            'idle' => $cpuData[4] ?? 0,
            'iowait' => $cpuData[5] ?? 0,
        ];
    }

    // CPU Temp
    $tempPaths = [
        '/sys/class/thermal/thermal_zone0/temp',
        '/sys/devices/virtual/thermal/thermal_zone0/temp',
        '/sys/class/hwmon/hwmon0/temp1_input',
        '/sys/class/hwmon/hwmon1/temp1_input',
    ];
    $info['cpu_temp'] = 0;
    foreach ($tempPaths as $p) {
        if (file_exists($p)) {
            $t = (int)trim(file_get_contents($p));
            if ($t > 0) {
                $info['cpu_temp'] = round($t / 1000, 1);
                break;
            }
        }
    }

    // RAM
    $memRaw = @file_get_contents('/proc/meminfo');
    if ($memRaw) {
        preg_match('/MemTotal:\s+(\d+)/', $memRaw, $m);
        $memTotal = (int)($m[1] ?? 0);
        preg_match('/MemAvailable:\s+(\d+)/', $memRaw, $m);
        $memAvail = (int)($m[1] ?? 0);
        $memUsed = $memTotal - $memAvail;
        $info['ram'] = [
            'total' => $memTotal,
            'used' => $memUsed,
            'available' => $memAvail,
            'percent' => $memTotal > 0 ? round(($memUsed / $memTotal) * 100, 1) : 0,
        ];
    }

    // Storage (SDCard /mnt/sdcard atau /)
    $storagePaths = ['/mnt/sdcard', '/'];
    $info['storage'] = [];
    foreach ($storagePaths as $sp) {
        $df = @disk_total_space($sp);
        $du = @disk_free_space($sp);
        if ($df && $du) {
            $label = ($sp === '/mnt/sdcard') ? 'SDCard' : 'Internal';
            $info['storage'][$label] = [
                'total' => $df,
                'used' => $df - $du,
                'free' => $du,
                'mount' => $sp,
                'percent' => round((($df - $du) / $df) * 100, 1),
            ];
        }
    }

    // SWAP
    $swapRaw = @file_get_contents('/proc/swaps');
    $info['swap'] = ['total' => 0, 'used' => 0, 'free' => 0, 'percent' => 0];
    if ($swapRaw) {
        $lines = explode("\n", $swapRaw);
        for ($i = 1; $i < count($lines); $i++) {
            $parts = preg_split('/\s+/', trim($lines[$i]));
            if (count($parts) >= 5) {
                $info['swap']['total'] += (int)$parts[2];
                $info['swap']['used'] += (int)$parts[3];
            }
        }
        $info['swap']['free'] = $info['swap']['total'] - $info['swap']['used'];
        if ($info['swap']['total'] > 0) {
            $info['swap']['percent'] = round(($info['swap']['used'] / $info['swap']['total']) * 100, 1);
        }
    }

    // ZRAM
    $info['zram'] = ['total' => 0, 'used' => 0, 'orig' => 0, 'percent' => 0];
    $zramDevices = glob('/sys/block/zram*');
    if (!empty($zramDevices)) {
        foreach ($zramDevices as $zdev) {
            $zname = basename($zdev);
            $zsize = @file_get_contents("/sys/block/$zname/disksize");
            $zused = @file_get_contents("/sys/block/$zname/ mm_stat");
            if ($zsize) {
                $info['zram']['total'] += (int)$zsize;
            }
            if ($zused) {
                $stat = explode(' ', trim($zused));
                if (isset($stat[0])) $info['zram']['orig'] += (int)$stat[0];
                if (isset($stat[1])) $info['zram']['used'] += (int)$stat[1];
            }
        }
        $info['zram']['orig_mb'] = round($info['zram']['orig'] / 1024, 1);
        if ($info['zram']['total'] > 0) {
            $info['zram']['percent'] = round(($info['zram']['used'] / $info['zram']['total']) * 100, 1);
        }
    }

    // Network RX/TX
    $netRaw = @file_get_contents('/proc/net/dev');
    $info['network'] = ['total_rx' => 0, 'total_tx' => 0, 'interfaces' => []];
    if ($netRaw) {
        $lines = explode("\n", $netRaw);
        for ($i = 2; $i < count($lines); $i++) {
            if (preg_match('/^\s*(eth|wlan|en|wl|br|bond)(\S+):\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $lines[$i], $m)) {
                $iface = $m[1] . $m[2];
                $rx = (int)$m[3];
                $tx = (int)$m[4];
                $info['network']['total_rx'] += $rx;
                $info['network']['total_tx'] += $tx;
                $info['network']['interfaces'][$iface] = ['rx' => $rx, 'tx' => $tx];
            }
        }
    }

    // Uptime
    $uptime = @file_get_contents('/proc/uptime');
    $info['uptime'] = $uptime ? (int)explode(' ', $uptime)[0] : 0;

    // Load average
    $load = @file_get_contents('/proc/loadavg');
    $info['load'] = $load ? explode(' ', $load) : [0, 0, 0];

    // Hostname
    $info['hostname'] = trim(@file_get_contents('/proc/sys/kernel/hostname') ?: gethostname());

    // OS
    $osRelease = @file_get_contents('/etc/os-release');
    $info['os'] = 'Armbian';
    if ($osRelease && preg_match('/PRETTY_NAME="(.+)"/', $osRelease, $m)) {
        $info['os'] = $m[1];
    }

    return $info;
}

// Fungsi format bytes
function formatBytes($bytes, $precision = 2) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    $bytes /= pow(1024, $pow);
    return round($bytes, $precision) . ' ' . $units[$pow];
}

// Fungsi format waktu uptime
function formatUptime($seconds) {
    $days = floor($seconds / 86400);
    $hours = floor(($seconds % 86400) / 3600);
    $minutes = floor(($seconds % 3600) / 60);
    $parts = [];
    if ($days > 0) $parts[] = "{$days}d";
    if ($hours > 0) $parts[] = "{$hours}h";
    $parts[] = "{$minutes}m";
    return implode(' ', $parts);
}

$sysInfo = getSystemInfo();

// Tentukan class tema
$themeClass = 'theme-' . htmlspecialchars($config['theme']);

// Cek apakah request AJAX
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');
    echo json_encode($sysInfo);
    exit;
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($config['site_name']) ?> - Dashboard</title>
    <link rel="stylesheet" href="css/<?= htmlspecialchars($config['theme']) ?>.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
</head>
<body class="<?= $themeClass ?>">
    <div class="container">
        <!-- Header -->
        <header class="header">
            <div class="header-left">
                <h1 class="site-title"><i class="fas fa-server"></i> <?= htmlspecialchars($config['site_name']) ?></h1>
                <span class="hostname"><?= htmlspecialchars($sysInfo['hostname']) ?></span>
            </div>
            <div class="header-right">
                <div class="theme-selector">
                    <label for="themeSelect"><i class="fas fa-palette"></i></label>
                    <select id="themeSelect" onchange="changeTheme(this.value)">
                        <option value="minimalist" <?= $config['theme'] === 'minimalist' ? 'selected' : '' ?>>Minimalist</option>
                        <option value="modern" <?= $config['theme'] === 'modern' ? 'selected' : '' ?>>Modern</option>
                        <option value="techno" <?= $config['theme'] === 'techno' ? 'selected' : '' ?>>Techno</option>
                        <option value="cute" <?= $config['theme'] === 'cute' ? 'selected' : '' ?>>Cute</option>
                    </select>
                </div>
                <div class="refresh-indicator">
                    <span id="refreshStatus"><i class="fas fa-sync-alt"></i></span>
                    <span id="lastUpdate"></span>
                </div>
            </div>
        </header>

        <!-- System Info Cards -->
        <div class="grid">
            <!-- CPU -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-microchip"></i>
                    <h2>CPU</h2>
                </div>
                <div class="card-body">
                    <div class="info-row">
                        <span class="label">Temperature</span>
                        <span class="value" id="cpuTemp"><?= $sysInfo['cpu_temp'] ?>°C</span>
                    </div>
                    <div class="info-row">
                        <span class="label">Usage</span>
                        <span class="value" id="cpuUsage">
                            <div class="progress-bar">
                                <div class="progress-fill" id="cpuUsageFill" style="width: 0%"></div>
                            </div>
                            <span id="cpuUsageText">0%</span>
                        </span>
                    </div>
                    <div class="info-row">
                        <span class="label">Load</span>
                        <span class="value"><?= implode(' / ', array_map(function($v) { return round((float)$v, 2); }, $sysInfo['load'])) ?></span>
                    </div>
                </div>
            </div>

            <!-- RAM -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-memory"></i>
                    <h2>RAM</h2>
                </div>
                <div class="card-body">
                    <div class="info-row">
                        <span class="label">Total</span>
                        <span class="value"><?= formatBytes($sysInfo['ram']['total'] * 1024) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Used</span>
                        <span class="value" id="ramUsed"><?= formatBytes($sysInfo['ram']['used'] * 1024) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Available</span>
                        <span class="value" id="ramAvail"><?= formatBytes($sysInfo['ram']['available'] * 1024) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Usage</span>
                        <span class="value">
                            <div class="progress-bar">
                                <div class="progress-fill" id="ramUsageFill" style="width: <?= $sysInfo['ram']['percent'] ?>%"></div>
                            </div>
                            <span id="ramUsageText"><?= $sysInfo['ram']['percent'] ?>%</span>
                        </span>
                    </div>
                </div>
            </div>

            <!-- Storage -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-database"></i>
                    <h2>Storage</h2>
                </div>
                <div class="card-body">
                    <?php foreach ($sysInfo['storage'] as $label => $st): ?>
                    <div class="storage-item">
                        <div class="info-row">
                            <span class="label"><?= htmlspecialchars($label) ?> <small>(<?= htmlspecialchars($st['mount']) ?>)</small></span>
                            <span class="value"><?= formatBytes($st['total']) ?></span>
                        </div>
                        <div class="info-row">
                            <span class="label">Used</span>
                            <span class="value" id="storageUsed_<?= $label ?>"><?= formatBytes($st['used']) ?></span>
                        </div>
                        <div class="info-row">
                            <span class="label">Free</span>
                            <span class="value" id="storageFree_<?= $label ?>"><?= formatBytes($st['free']) ?></span>
                        </div>
                        <div class="info-row">
                            <span class="label">Usage</span>
                            <span class="value">
                                <div class="progress-bar">
                                    <div class="progress-fill storage-fill" style="width: <?= $st['percent'] ?>%"></div>
                                </div>
                                <span id="storagePercent_<?= $label ?>"><?= $st['percent'] ?>%</span>
                            </span>
                        </div>
                    </div>
                    <?php endforeach; ?>
                </div>
            </div>

            <!-- SWAP & ZRAM -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-exchange-alt"></i>
                    <h2>SWAP / ZRAM</h2>
                </div>
                <div class="card-body">
                    <h3 class="sub-title">SWAP</h3>
                    <div class="info-row">
                        <span class="label">Total</span>
                        <span class="value"><?= formatBytes($sysInfo['swap']['total'] * 1024) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Used</span>
                        <span class="value" id="swapUsed"><?= formatBytes($sysInfo['swap']['used'] * 1024) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Usage</span>
                        <span class="value">
                            <div class="progress-bar">
                                <div class="progress-fill swap-fill" style="width: <?= $sysInfo['swap']['percent'] ?>%"></div>
                            </div>
                            <span id="swapPercent"><?= $sysInfo['swap']['percent'] ?>%</span>
                        </span>
                    </div>

                    <h3 class="sub-title">ZRAM</h3>
                    <div class="info-row">
                        <span class="label">Total</span>
                        <span class="value"><?= formatBytes($sysInfo['zram']['total']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Used</span>
                        <span class="value" id="zramUsed"><?= formatBytes($sysInfo['zram']['used']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Orig Data</span>
                        <span class="value"><?= $sysInfo['zram']['orig_mb'] ?> MB</span>
                    </div>
                    <div class="info-row">
                        <span class="label">Usage</span>
                        <span class="value">
                            <div class="progress-bar">
                                <div class="progress-fill zram-fill" style="width: <?= $sysInfo['zram']['percent'] ?>%"></div>
                            </div>
                            <span id="zramPercent"><?= $sysInfo['zram']['percent'] ?>%</span>
                        </span>
                    </div>
                </div>
            </div>

            <!-- Network -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-network-wired"></i>
                    <h2>Network</h2>
                </div>
                <div class="card-body">
                    <div class="info-row">
                        <span class="label">Total RX</span>
                        <span class="value" id="totalRX"><?= formatBytes($sysInfo['network']['total_rx']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Total TX</span>
                        <span class="value" id="totalTX"><?= formatBytes($sysInfo['network']['total_tx']) ?></span>
                    </div>
                    <div class="network-interfaces">
                        <?php foreach ($sysInfo['network']['interfaces'] as $iface => $data): ?>
                        <div class="interface-row">
                            <span class="iface-name"><?= htmlspecialchars($iface) ?></span>
                            <span class="iface-stats">
                                <i class="fas fa-arrow-down"></i> <?= formatBytes($data['rx']) ?>
                                <i class="fas fa-arrow-up"></i> <?= formatBytes($data['tx']) ?>
                            </span>
                        </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>

            <!-- System Info -->
            <div class="card">
                <div class="card-header">
                    <i class="fas fa-info-circle"></i>
                    <h2>System</h2>
                </div>
                <div class="card-body">
                    <div class="info-row">
                        <span class="label">OS</span>
                        <span class="value"><?= htmlspecialchars($sysInfo['os']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Hostname</span>
                        <span class="value"><?= htmlspecialchars($sysInfo['hostname']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">Uptime</span>
                        <span class="value"><?= formatUptime($sysInfo['uptime']) ?></span>
                    </div>
                    <div class="info-row">
                        <span class="label">PHP Version</span>
                        <span class="value"><?= phpversion() ?></span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Aplikasi Terinstall -->
        <section class="section">
            <div class="section-header">
                <h2><i class="fas fa-th-large"></i> Aplikasi Terinstall</h2>
            </div>
            <div class="apps-grid" id="appsGrid">
                <?php
                $apps = [
                    ['name' => 'File Manager', 'icon' => 'fas fa-folder-open', 'url' => 'file-manager/', 'desc' => 'Kelola file sistem'],
                    ['name' => 'phpMyAdmin', 'icon' => 'fas fa-database', 'url' => 'phpmyadmin/', 'desc' => 'Manajemen database', 'check' => '/usr/share/phpmyadmin'],
                    ['name' => 'Netdata', 'icon' => 'fas fa-chart-line', 'url' => 'http://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':19999', 'desc' => 'Monitoring sistem', 'check' => '/usr/sbin/netdata'],
                    ['name' => 'Cockpit', 'icon' => 'fas fa-cocktail', 'url' => 'http://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':9090', 'desc' => 'Manajemen server', 'check' => '/usr/bin/cockpit-bridge'],
                    ['name' => 'Portainer', 'icon' => 'fab fa-docker', 'url' => 'https://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':9443', 'desc' => 'Manajemen container', 'check' => '/usr/bin/docker'],
                    ['name' => 'Jellyfin', 'icon' => 'fas fa-film', 'url' => 'http://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':8096', 'desc' => 'Media server', 'check' => '/usr/bin/jellyfin'],
                    ['name' => 'Transmission', 'icon' => 'fas fa-download', 'url' => 'http://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':9091', 'desc' => 'Torrent client', 'check' => '/usr/bin/transmission-daemon'],
                    ['name' => 'Syncthing', 'icon' => 'fas fa-sync', 'url' => 'http://' . ($_SERVER['SERVER_ADDR'] ?? 'localhost') . ':8384', 'desc' => 'Sinkronisasi file', 'check' => '/usr/bin/syncthing'],
                    ['name' => 'My Document', 'icon' => 'fas fa-file-alt', 'url' => 'My Document/', 'desc' => 'Dokumen pribadi'],
                    ['name' => 'My Music', 'icon' => 'fas fa-music', 'url' => 'My Music/', 'desc' => 'Koleksi musik'],
                    ['name' => 'My Pictures', 'icon' => 'fas fa-image', 'url' => 'My Pictures/', 'desc' => 'Album foto'],
                    ['name' => 'My Video', 'icon' => 'fas fa-video', 'url' => 'My Video/', 'desc' => 'Koleksi video'],
                ];
                foreach ($apps as $app):
                    $isInstalled = true;
                    if (isset($app['check'])) {
                        $isInstalled = file_exists($app['check']) || is_dir($app['check']);
                    }
                    if (!$isInstalled) continue;
                ?>
                <a href="<?= htmlspecialchars($app['url']) ?>" class="app-card" target="_blank">
                    <div class="app-icon"><i class="<?= $app['icon'] ?>"></i></div>
                    <div class="app-info">
                        <span class="app-name"><?= htmlspecialchars($app['name']) ?></span>
                        <span class="app-desc"><?= htmlspecialchars($app['desc']) ?></span>
                    </div>
                </a>
                <?php endforeach; ?>
            </div>
        </section>

        <!-- Service Manager -->
        <section class="section">
            <div class="section-header">
                <h2><i class="fas fa-cogs"></i> Service Manager</h2>
            </div>
            <div class="services-grid" id="servicesGrid">
                <?php
                $services = [
                    'nginx', 'apache2', 'php8.2-fpm', 'mariadb', 'mysql',
                    'redis-server', 'squid', 'pihole-FTL', 'dnsmasq',
                    'docker', 'netdata', 'jellyfin', 'transmission-daemon',
                    'syncthing@root', 'cockpit', 'ssh', 'cron',
                ];
                foreach ($services as $svc):
                    $isActive = false;
                    $isEnabled = false;
                    $output = [];
                    exec("systemctl is-active $svc 2>/dev/null", $output, $rcActive);
                    $isActive = trim(implode('', $output)) === 'active';
                    $output = [];
                    exec("systemctl is-enabled $svc 2>/dev/null", $output, $rcEnabled);
                    $isEnabled = trim(implode('', $output)) === 'enabled' || trim(implode('', $output)) === 'static';
                    if (!$isActive && !$isEnabled) continue;
                ?>
                <div class="service-card" data-service="<?= htmlspecialchars($svc) ?>">
                    <div class="service-header">
                        <span class="service-name"><?= htmlspecialchars($svc) ?></span>
                        <span class="service-status <?= $isActive ? 'status-active' : 'status-inactive' ?>">
                            <i class="fas fa-circle"></i> <?= $isActive ? 'Active' : 'Inactive' ?>
                        </span>
                    </div>
                    <div class="service-actions">
                        <button class="btn btn-sm btn-status" onclick="serviceAction('<?= htmlspecialchars($svc) ?>', 'status')" title="Status"><i class="fas fa-info-circle"></i></button>
                        <button class="btn btn-sm btn-start" onclick="serviceAction('<?= htmlspecialchars($svc) ?>', 'start')" title="Start"><i class="fas fa-play"></i></button>
                        <button class="btn btn-sm btn-stop" onclick="serviceAction('<?= htmlspecialchars($svc) ?>', 'stop')" title="Stop"><i class="fas fa-stop"></i></button>
                        <button class="btn btn-sm btn-restart" onclick="serviceAction('<?= htmlspecialchars($svc) ?>', 'restart')" title="Restart"><i class="fas fa-sync-alt"></i></button>
                    </div>
                </div>
                <?php endforeach; ?>
            </div>
        </section>

        <!-- Footer -->
        <footer class="footer">
            <p><?= htmlspecialchars($config['site_name']) ?> &copy; <?= date('Y') ?> | Powered by Armbian on TV Box</p>
        </footer>
    </div>

    <!-- Service Action Modal -->
    <div id="serviceModal" class="modal">
        <div class="modal-content">
            <div class="modal-header">
                <h3><i class="fas fa-terminal"></i> <span id="modalTitle">Service Action</span></h3>
                <span class="modal-close" onclick="closeModal()">&times;</span>
            </div>
            <div class="modal-body">
                <pre id="modalOutput"></pre>
            </div>
            <div class="modal-footer">
                <button class="btn btn-primary" onclick="closeModal()">Tutup</button>
            </div>
        </div>
    </div>

    <script src="js/main.js"></script>
</body>
</html>
