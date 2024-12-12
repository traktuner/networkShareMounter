<?php
define('DIR_BASE', __DIR__);
define('DIR_STATS', DIR_BASE . '/stats');

$required_parameters = ['bundleid', 'uuid', 'version'];
$optional_parameters = ['osversion'];
$all_parameters = array_merge($required_parameters, $optional_parameters);
$request_parameters = array_keys($_GET);

$validation = [
    'bundleid' => ['options' => ['regexp' => "/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+[0-9a-z_]$/i"]],
    'version' => ['options' => ['regexp' => "/^[1-9]\d*(\.[1-9]\d*)*/"]],
    'osversion' => ['options' => ['regexp' => "/^\d+(\.\d+)*$/"]]
];

if (!empty($_GET) && !array_diff($required_parameters, $request_parameters) && !array_diff($request_parameters, $all_parameters)) {
    $data = ['request_time' => date(DATE_W3C), 'remote_address' => $_SERVER['REMOTE_ADDR']] + $_GET;

    foreach ($required_parameters as $param) {
        if (isset($validation[$param]) && filter_var($_GET[$param], FILTER_VALIDATE_REGEXP, $validation[$param]) === false) {
            exit;
        }
    }

    if (isset($_GET['osversion']) && filter_var($_GET['osversion'], FILTER_VALIDATE_REGEXP, $validation['osversion']) === false) {
        exit;
    }

    $handle = fopen(DIR_STATS . '/stats-' . date('Y-m') . '.csv', 'a');
    fputcsv($handle, $data, "\t");
    fclose($handle);
}

function isValidUuid($uuid) {
    return is_string($uuid) && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $uuid) === 1;
}