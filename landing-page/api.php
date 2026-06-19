<?php
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['service'], $_POST['action'])) {
    $service = escapeshellarg($_POST['service']);
    $action = escapeshellarg($_POST['action']);

    if (!in_array($_POST['action'], ['status', 'start', 'stop', 'restart'])) {
        echo json_encode(['error' => 'Invalid action']);
        exit;
    }

    $output = [];
    $returnVar = 0;
    exec("systemctl $action $service 2>&1", $output, $returnVar);
    echo json_encode([
        'success' => $returnVar === 0,
        'output' => implode("\n", $output)
    ]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $info = [];

    $cpuRaw = @file_get_contents('/proc/stat');
    if ($cpuRaw) {
        $cpuLine = explode("\n", $cpuRaw)[0];
        $cpuData = preg_split('/\s+/', $cpuLine);
        $info['cpu'] = [
            'user' => (int)($cpuData[1] ?? 0),
            'nice' => (int)($cpuData[2] ?? 0),
            'system' => (int)($cpuData[3] ?? 0),
            'idle' => (int)($cpuData[4] ?? 0),
        ];
    }

    $tempPaths = [
        '/sys/class/thermal/thermal_zone0/temp',
        '/sys/devices/virtual/thermal/thermal_zone0/temp',
    ];
    $info['cpu_temp'] = 0;
    foreach ($tempPaths as $p) {
        if (file_exists($p)) {
            $t = (int)trim(@file_get_contents($p));
            if ($t > 0) { $info['cpu_temp'] = round($t / 1000, 1); break; }
        }
    }

    $memRaw = @file_get_contents('/proc/meminfo');
    if ($memRaw) {
        preg_match('/MemTotal:\s+(\d+)/', $memRaw, $m);
        $total = (int)($m[1] ?? 0);
        preg_match('/MemAvailable:\s+(\d+)/', $memRaw, $m);
        $avail = (int)($m[1] ?? 0);
        $info['ram'] = [
            'total' => $total, 'used' => $total - $avail,
            'available' => $avail,
            'percent' => $total > 0 ? round((($total - $avail) / $total) * 100, 1) : 0,
        ];
    }

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

    $netRaw = @file_get_contents('/proc/net/dev');
    $info['network'] = ['total_rx' => 0, 'total_tx' => 0];
    if ($netRaw) {
        $lines = explode("\n", $netRaw);
        for ($i = 2; $i < count($lines); $i++) {
            if (preg_match('/^\s*(eth|wlan|en|wl|br|bond)\S+:\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/', $lines[$i], $m)) {
                $info['network']['total_rx'] += (int)$m[2];
                $info['network']['total_tx'] += (int)$m[3];
            }
        }
    }

    echo json_encode($info);
    exit;
}

http_response_code(405);
echo json_encode(['error' => 'Method Not Allowed']);
