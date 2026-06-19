<?php
session_start();

$rootPath = realpath($_GET['path'] ?? '/') ?: '/';
$allowedRoots = ['/', '/var/www', '/opt/miniserver/www'];

// Validasi path
$isValid = false;
foreach ($allowedRoots as $allowed) {
    $realAllowed = realpath($allowed) ?: $allowed;
    if (strpos($rootPath, $realAllowed) === 0) {
        $isValid = true;
        break;
    }
}
if (!$isValid) {
    $rootPath = '/';
}

$parentDir = dirname($rootPath);
$currentPath = $rootPath;

// Handle actions
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    switch ($action) {
        case 'create_dir':
            $name = basename($_POST['name'] ?? '');
            if ($name) {
                $newPath = $currentPath . '/' . $name;
                if (!file_exists($newPath)) {
                    mkdir($newPath, 0755, true);
                    $message = "Folder '$name' berhasil dibuat";
                    $messageType = 'success';
                } else {
                    $message = "Folder '$name' sudah ada";
                    $messageType = 'error';
                }
            }
            break;

        case 'create_file':
            $name = basename($_POST['name'] ?? '');
            if ($name) {
                $newPath = $currentPath . '/' . $name;
                if (!file_exists($newPath)) {
                    file_put_contents($newPath, '');
                    $message = "File '$name' berhasil dibuat";
                    $messageType = 'success';
                } else {
                    $message = "File '$name' sudah ada";
                    $messageType = 'error';
                }
            }
            break;

        case 'delete':
            $target = realpath($_POST['target'] ?? '') ?: '';
            if ($target && strpos($target, $currentPath) === 0) {
                if (is_dir($target)) {
                    $files = new RecursiveIteratorIterator(
                        new RecursiveDirectoryIterator($target, RecursiveDirectoryIterator::SKIP_DOTS),
                        RecursiveIteratorIterator::CHILD_FIRST
                    );
                    foreach ($files as $f) {
                        $f->isDir() ? rmdir($f->getRealPath()) : unlink($f->getRealPath());
                    }
                    rmdir($target);
                } else {
                    unlink($target);
                }
                $message = "Berhasil dihapus";
                $messageType = 'success';
            }
            break;

        case 'upload':
            if (isset($_FILES['file']) && $_FILES['file']['error'] === UPLOAD_ERR_OK) {
                $dest = $currentPath . '/' . basename($_FILES['file']['name']);
                move_uploaded_file($_FILES['file']['tmp_name'], $dest);
                $message = "File berhasil diupload";
                $messageType = 'success';
            }
            break;

        case 'save_file':
            $target = realpath($_POST['target'] ?? '') ?: '';
            if ($target && strpos($target, $currentPath) === 0 && is_file($target)) {
                $content = $_POST['content'] ?? '';
                file_put_contents($target, $content);
                $message = "File berhasil disimpan";
                $messageType = 'success';
            }
            break;
    }
}

// Baca direktori
$items = [];
$editing = false;
$editContent = '';
$editPath = '';

if (isset($_GET['edit'])) {
    $editPath = realpath($_GET['edit']) ?: '';
    if ($editPath && strpos($editPath, $currentPath) === 0 && is_file($editPath) && is_readable($editPath)) {
        $editing = true;
        $editContent = file_get_contents($editPath);
        $ext = strtolower(pathinfo($editPath, PATHINFO_EXTENSION));
        $editableExts = ['txt', 'php', 'html', 'htm', 'css', 'js', 'json', 'xml', 'ini', 'conf', 'sh', 'py', 'md', 'yml', 'yaml', 'cfg', 'env', 'sql', 'htaccess'];
        if (!in_array($ext, $editableExts)) {
            $editing = false;
            $message = "Tipe file tidak dapat diedit";
            $messageType = 'error';
        }
    }
}

if (is_dir($currentPath)) {
    $dh = opendir($currentPath);
    if ($dh) {
        while (($file = readdir($dh)) !== false) {
            if ($file === '.' || $file === '..') continue;
            $fullPath = $currentPath . '/' . $file;
            $stat = stat($fullPath);
            $items[] = [
                'name' => $file,
                'path' => $fullPath,
                'type' => is_dir($fullPath) ? 'dir' : 'file',
                'size' => is_file($fullPath) ? $stat['size'] : 0,
                'perms' => substr(sprintf('%o', fileperms($fullPath)), -4),
                'modified' => $stat['mtime'],
                'owner' => function_exists('posix_getpwuid') ? posix_getpwuid($stat['uid'])['name'] ?? $stat['uid'] : $stat['uid'],
            ];
        }
        closedir($dh);
    }
    usort($items, function($a, $b) {
        if ($a['type'] !== $b['type']) return $a['type'] === 'dir' ? -1 : 1;
        return strcasecmp($a['name'], $b['name']);
    });
}

function formatSize($bytes) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);
    return round($bytes / pow(1024, $pow), 1) . ' ' . $units[$pow];
}

function getFileIcon($name, $type) {
    if ($type === 'dir') {
        $lower = strtolower($name);
        if ($lower === 'my document') return 'fa-folder-open';
        if ($lower === 'my music') return 'fa-music';
        if ($lower === 'my pictures' || $lower === 'my photo') return 'fa-image';
        if ($lower === 'my video') return 'fa-video';
        return 'fa-folder';
    }
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    $icons = [
        'php' => 'fa-file-code', 'html' => 'fa-file-code', 'htm' => 'fa-file-code',
        'css' => 'fa-file-code', 'js' => 'fa-file-code', 'json' => 'fa-file-code',
        'xml' => 'fa-file-code', 'py' => 'fa-file-code', 'sh' => 'fa-terminal',
        'txt' => 'fa-file-alt', 'md' => 'fa-file-alt', 'ini' => 'fa-file-alt',
        'conf' => 'fa-file-alt', 'cfg' => 'fa-file-alt', 'env' => 'fa-file-alt',
        'jpg' => 'fa-file-image', 'jpeg' => 'fa-file-image', 'png' => 'fa-file-image',
        'gif' => 'fa-file-image', 'webp' => 'fa-file-image', 'svg' => 'fa-file-image',
        'mp3' => 'fa-file-audio', 'wav' => 'fa-file-audio', 'flac' => 'fa-file-audio',
        'mp4' => 'fa-file-video', 'avi' => 'fa-file-video', 'mkv' => 'fa-file-video',
        'zip' => 'fa-file-archive', 'tar' => 'fa-file-archive', 'gz' => 'fa-file-archive',
        'pdf' => 'fa-file-pdf', 'doc' => 'fa-file-word', 'docx' => 'fa-file-word',
        'xls' => 'fa-file-excel', 'xlsx' => 'fa-file-excel',
        'sql' => 'fa-database', 'db' => 'fa-database',
    ];
    return $icons[$ext] ?? 'fa-file';
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>File Manager - MiniServer</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <style>
        :root {
            --bg: #0f0f1a;
            --bg2: #1a1a2e;
            --card: rgba(255,255,255,0.04);
            --text: #e4e4e7;
            --text2: #a1a1aa;
            --accent: #6366f1;
            --border: rgba(255,255,255,0.08);
            --radius: 12px;
        }
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: 'Inter', -apple-system, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height:100vh;
        }
        .container { max-width:1400px; margin:0 auto; padding:20px; }

        .header {
            display:flex; justify-content:space-between; align-items:center;
            padding:16px 24px; background:var(--card); border:1px solid var(--border);
            border-radius:var(--radius); margin-bottom:20px;
        }
        .header h1 { font-size:1.2em; }
        .header h1 i { color:var(--accent); margin-right:10px; }
        .header-actions { display:flex; gap:10px; }
        .header-actions a, .header-actions button {
            padding:8px 16px; border:1px solid var(--border); border-radius:8px;
            background:transparent; color:var(--text); cursor:pointer;
            text-decoration:none; font-size:0.85em; transition:all 0.2s;
        }
        .header-actions a:hover, .header-actions button:hover {
            border-color:var(--accent); color:var(--accent);
        }

        .breadcrumb {
            display:flex; align-items:center; gap:8px; flex-wrap:wrap;
            padding:12px 16px; background:var(--card); border:1px solid var(--border);
            border-radius:var(--radius); margin-bottom:16px; font-size:0.85em;
        }
        .breadcrumb a { color:var(--accent); text-decoration:none; }
        .breadcrumb a:hover { text-decoration:underline; }
        .breadcrumb .sep { color:var(--text2); }

        .message {
            padding:12px 16px; border-radius:var(--radius); margin-bottom:16px;
            font-size:0.85em;
        }
        .message.success { background:rgba(34,197,94,0.1); border:1px solid rgba(34,197,94,0.2); color:#22c55e; }
        .message.error { background:rgba(239,68,68,0.1); border:1px solid rgba(239,68,68,0.2); color:#ef4444; }

        .toolbar {
            display:flex; gap:10px; margin-bottom:16px; flex-wrap:wrap;
        }
        .toolbar form { display:flex; gap:8px; align-items:center; }
        .toolbar input[type=text] {
            padding:8px 12px; background:var(--bg2); border:1px solid var(--border);
            border-radius:8px; color:var(--text); font-size:0.85em;
        }
        .toolbar input[type=text]:focus { outline:none; border-color:var(--accent); }
        .toolbar button, .toolbar .btn {
            padding:8px 14px; border:1px solid var(--border); border-radius:8px;
            background:transparent; color:var(--text); cursor:pointer; font-size:0.85em;
            transition:all 0.2s; text-decoration:none; display:inline-flex; align-items:center; gap:6px;
        }
        .toolbar button:hover, .toolbar .btn:hover {
            border-color:var(--accent); color:var(--accent);
        }
        .toolbar .btn-primary { background:var(--accent); color:white; border-color:var(--accent); }
        .toolbar .btn-primary:hover { background:#5558e6; }

        table { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--border); border-radius:var(--radius); overflow:hidden; }
        th, td { padding:10px 14px; text-align:left; border-bottom:1px solid var(--border); font-size:0.85em; }
        th { background:var(--bg2); font-weight:600; color:var(--text2); text-transform:uppercase; font-size:0.75em; letter-spacing:0.5px; }
        tr:hover { background:rgba(255,255,255,0.02); }
        td a { color:var(--text); text-decoration:none; display:flex; align-items:center; gap:8px; }
        td a:hover { color:var(--accent); }
        .file-icon { width:20px; text-align:center; color:var(--accent); }
        .dir-icon { width:20px; text-align:center; color:var(--warning); }

        .actions { display:flex; gap:6px; }
        .actions a, .actions button {
            padding:4px 10px; border:1px solid var(--border); border-radius:6px;
            background:transparent; color:var(--text2); cursor:pointer; font-size:0.8em;
            text-decoration:none; transition:all 0.2s;
        }
        .actions a:hover, .actions button:hover {
            color:var(--accent); border-color:var(--accent);
        }
        .actions .btn-edit:hover { color:#22c55e; border-color:#22c55e; }
        .actions .btn-delete:hover { color:#ef4444; border-color:#ef4444; }

        .editor { background:var(--card); border:1px solid var(--border); border-radius:var(--radius); overflow:hidden; }
        .editor-header {
            display:flex; justify-content:space-between; align-items:center;
            padding:12px 16px; border-bottom:1px solid var(--border);
        }
        .editor-body textarea {
            width:100%; min-height:400px; padding:16px;
            background:#0a0a0a; color:#22c55e; border:none;
            font-family:'Consolas','Courier New',monospace; font-size:0.9em; resize:vertical;
        }
        .editor-body textarea:focus { outline:none; }
        .editor-footer { padding:12px 16px; border-top:1px solid var(--border); display:flex; gap:10px; justify-content:flex-end; }

        .upload-form input[type=file] { display:none; }
        .upload-form label {
            padding:8px 14px; border:1px solid var(--border); border-radius:8px;
            cursor:pointer; font-size:0.85em; transition:all 0.2s;
        }
        .upload-form label:hover { border-color:var(--accent); color:var(--accent); }

        .footer { text-align:center; padding:20px; color:var(--text2); font-size:0.8em; }
        .size { color:var(--text2); font-size:0.8em; }
        .perms { font-family:'Consolas',monospace; font-size:0.8em; color:var(--text2); }

        @media(max-width:768px) {
            .header { flex-direction:column; gap:12px; }
            .toolbar { flex-direction:column; }
            .toolbar form { width:100%; }
            .toolbar input[type=text] { flex:1; }
            th:nth-child(3), th:nth-child(4), th:nth-child(5),
            td:nth-child(3), td:nth-child(4), td:nth-child(5) { display:none; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-folder-open"></i> File Manager</h1>
            <div class="header-actions">
                <a href="../"><i class="fas fa-arrow-left"></i> Landing Page</a>
                <a href="?path=/"><i class="fas fa-home"></i> Root</a>
                <a href="?path=/var/www"><i class="fas fa-globe"></i> /var/www</a>
                <a href="?path=/opt/miniserver/www"><i class="fas fa-folder"></i> My Files</a>
            </div>
        </div>

        <div class="breadcrumb">
            <a href="?path=/"><i class="fas fa-home"></i></a>
            <span class="sep">/</span>
            <?php
            $parts = explode('/', trim($currentPath, '/'));
            $cumulative = '';
            foreach ($parts as $part) {
                if ($part === '') continue;
                $cumulative .= '/' . $part;
                echo '<a href="?path=' . urlencode($cumulative) . '">' . htmlspecialchars($part) . '</a>';
                echo '<span class="sep">/</span>';
            }
            ?>
        </div>

        <?php if ($message): ?>
        <div class="message <?= $messageType ?>">
            <i class="fas fa-<?= $messageType === 'success' ? 'check-circle' : 'exclamation-circle' ?>"></i>
            <?= htmlspecialchars($message) ?>
        </div>
        <?php endif; ?>

        <?php if ($editing): ?>
        <div class="editor">
            <div class="editor-header">
                <span><i class="fas fa-edit"></i> Edit: <?= htmlspecialchars(basename($editPath)) ?></span>
                <span class="size"><?= htmlspecialchars($editPath) ?></span>
            </div>
            <form method="POST">
                <input type="hidden" name="action" value="save_file">
                <input type="hidden" name="target" value="<?= htmlspecialchars($editPath) ?>">
                <div class="editor-body">
                    <textarea name="content" spellcheck="false"><?= htmlspecialchars($editContent) ?></textarea>
                </div>
                <div class="editor-footer">
                    <a href="?path=<?= urlencode($currentPath) ?>" class="btn" style="text-decoration:none;">Batal</a>
                    <button type="submit" class="btn btn-primary">Simpan</button>
                </div>
            </form>
        </div>
        <?php else: ?>

        <div class="toolbar">
            <form method="POST" style="display:flex;gap:8px;">
                <input type="hidden" name="action" value="create_dir">
                <input type="text" name="name" placeholder="Nama folder..." required>
                <button type="submit"><i class="fas fa-folder-plus"></i> Folder</button>
            </form>
            <form method="POST" style="display:flex;gap:8px;">
                <input type="hidden" name="action" value="create_file">
                <input type="text" name="name" placeholder="Nama file..." required>
                <button type="submit"><i class="fas fa-file-plus"></i> File</button>
            </form>
            <form class="upload-form" method="POST" enctype="multipart/form-data">
                <input type="hidden" name="action" value="upload">
                <label for="fileUpload"><i class="fas fa-upload"></i> Upload</label>
                <input type="file" name="file" id="fileUpload" onchange="this.form.submit()">
            </form>
        </div>

        <table>
            <thead>
                <tr>
                    <th>Nama</th>
                    <th>Ukuran</th>
                    <th>Permissions</th>
                    <th>Owner</th>
                    <th>Modified</th>
                    <th>Aksi</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($parentDir !== $currentPath): ?>
                <tr>
                    <td colspan="6">
                        <a href="?path=<?= urlencode($parentDir) ?>">
                            <i class="fas fa-level-up-alt" style="color:var(--accent)"></i> ..
                        </a>
                    </td>
                </tr>
                <?php endif; ?>

                <?php foreach ($items as $item):
                    $icon = $item['type'] === 'dir' ? 'dir-icon' : 'file-icon';
                ?>
                <tr>
                    <td>
                        <?php if ($item['type'] === 'dir'): ?>
                        <a href="?path=<?= urlencode($item['path']) ?>">
                            <i class="fas <?= getFileIcon($item['name'], 'dir') ?> <?= $icon ?>"></i>
                            <?= htmlspecialchars($item['name']) ?>
                        </a>
                        <?php else: ?>
                        <a href="?path=<?= urlencode($currentPath) ?>&edit=<?= urlencode($item['path']) ?>">
                            <i class="fas <?= getFileIcon($item['name'], 'file') ?> <?= $icon ?>"></i>
                            <?= htmlspecialchars($item['name']) ?>
                        </a>
                        <?php endif; ?>
                    </td>
                    <td class="size"><?= $item['type'] === 'file' ? formatSize($item['size']) : '—' ?></td>
                    <td class="perms"><?= $item['perms'] ?></td>
                    <td class="size"><?= htmlspecialchars($item['owner']) ?></td>
                    <td class="size"><?= date('d/m/Y H:i', $item['modified']) ?></td>
                    <td>
                        <div class="actions">
                            <?php if ($item['type'] === 'file'): ?>
                            <a href="?path=<?= urlencode($currentPath) ?>&edit=<?= urlencode($item['path']) ?>" class="btn-edit" title="Edit"><i class="fas fa-edit"></i></a>
                            <?php endif; ?>
                            <form method="POST" onsubmit="return confirm('Hapus <?= htmlspecialchars($item['name']) ?>?')">
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="target" value="<?= htmlspecialchars($item['path']) ?>">
                                <button type="submit" class="btn-delete" title="Hapus"><i class="fas fa-trash"></i></button>
                            </form>
                        </div>
                    </td>
                </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>

        <footer class="footer">
            <p>MiniServer File Manager &copy; <?= date('Y') ?></p>
        </footer>
    </div>
</body>
</html>
