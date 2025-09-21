<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// اتصال بقاعدة البيانات
$servername = "localhost";
$username = "dramaxboxbbs_series"; // استبدل باسم المستخدم
$password = "dramaxboxbbs_series"; // استبدل بكلمة المرور
$dbname = "dramaxboxbbs_series"; // استبدل باسم قاعدة البيانات
// إنشاء الاتصال
$conn = new mysqli($servername, $username, $password, $dbname);

// التحقق من الاتصال
if ($conn->connect_error) {
    die(json_encode(["status" => "error", "message" => "فشل الاتصال: " . $conn->connect_error]));
}

// إنشاء الجدول إذا لم يكن موجوداً
$createTable = "CREATE TABLE IF NOT EXISTS Revo_Shorts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    config_key VARCHAR(50) NOT NULL UNIQUE,
    value INT NOT NULL DEFAULT 1
)";
$conn->query($createTable);

// ضمان وجود السجلات الأساسية
function ensureRecord($conn, $key, $default) {
    $stmt = $conn->prepare("SELECT COUNT(*) as cnt FROM Revo_Shorts WHERE config_key = ?");
    $stmt->bind_param("s", $key);
    $stmt->execute();
    $res = $stmt->get_result()->fetch_assoc();
    if ((int)$res['cnt'] === 0) {
        $ins = $conn->prepare("INSERT INTO Revo_Shorts (config_key, value) VALUES (?, ?)");
        $ins->bind_param("si", $key, $default);
        $ins->execute();
    }
}
ensureRecord($conn, 'app_mode', 1); // 1 = paid default
ensureRecord($conn, 'free_mode_ads', 1); // 1 = ads enabled by default in free mode

// دوال مساعدة
function getConfig($conn, $key) {
    $stmt = $conn->prepare("SELECT value FROM Revo_Shorts WHERE config_key = ?");
    $stmt->bind_param("s", $key);
    $stmt->execute();
    $res = $stmt->get_result();
    if ($res && $row = $res->fetch_assoc()) {
        return (int)$row['value'];
    }
    return null;
}

function updateConfig($conn, $key, $value) {
    $value = (int)$value;
    $stmt = $conn->prepare("UPDATE Revo_Shorts SET value = ? WHERE config_key = ?");
    $stmt->bind_param("is", $value, $key);
    if ($stmt->execute()) return true;
    return false;
}

// معالجة الطلبات
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $app_mode = getConfig($conn, 'app_mode');
    $free_mode_ads = getConfig($conn, 'free_mode_ads'); // 0 = no ads in free-mode, 1 = ads in free-mode
    echo json_encode(["status" => "success", "app_mode" => $app_mode, "free_mode_ads" => $free_mode_ads]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = json_decode(file_get_contents('php://input'), true);

    // تحقق إداري بسيط
    if (!isset($data['admin_token']) || $data['admin_token'] !== 'my_secret_token_123') {
        echo json_encode(["status" => "error", "message" => "غير مصرح"]);
        exit;
    }

    $updated = [];
    if (isset($data['app_mode'])) {
        if ($data['app_mode'] === 0 || $data['app_mode'] === 1) {
            updateConfig($conn, 'app_mode', $data['app_mode']);
            $updated['app_mode'] = $data['app_mode'];
        }
    }
    if (isset($data['free_mode_ads'])) {
        if ($data['free_mode_ads'] === 0 || $data['free_mode_ads'] === 1) {
            updateConfig($conn, 'free_mode_ads', $data['free_mode_ads']);
            $updated['free_mode_ads'] = $data['free_mode_ads'];
        }
    }

    if (!empty($updated)) {
        echo json_encode(["status" => "success", "updated" => $updated]);
    } else {
        echo json_encode(["status" => "error", "message" => "لم يتم تمرير معلمات صحيحة للتحديث"]);
    }
    exit;
}

$conn->close();
?>