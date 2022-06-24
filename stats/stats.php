<?php
# define some constants
define('DIR_BASE', __DIR__);
define('DIR_STATS', DIR_BASE . '/stats');

# define needed parameters
$parameters = [
    'bundleid',
    'uuid',
    'version'
];
$request_parameters = array_keys($_GET);

# validation config for bundleid and version
$validation = [
    'bundleid' => [
        'options' => [
            'regexp' => "/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+[0-9a-z_]$/i"
        ]
    ],
    'version' => [
        'options' => [
            'regexp' => "/^[1-9]\d*(\.[1-9]\d*)*/"
        ]
    ]
];

# only proceed if the request consists of nothing but the needed parameters
if (!empty($_GET) and ($request_parameters === $parameters))
{
    # fill data with request time and $_GET
    $data = [
                'request_time' => date(DATE_W3C),
                'remote_address' => $_SERVER['REMOTE_ADDR']
            ] + $_GET;

    # validate stuff
    if (
        filter_var($_GET['bundleid'], FILTER_VALIDATE_REGEXP, $validation['bundleid']) === false
        or
        isValidUuid($_GET['uuid']) === false
        or
        filter_var($_GET['version'], FILTER_VALIDATE_REGEXP, $validation['version']) === false
    ) {
        exit;
    }

    # now write data to log file
    $handle = fopen(DIR_STATS . '/stats-' . date('Y-m') . '.csv', 'a');
    fputcsv(
        $handle,
        $data,
        "\t"
    );
    fclose($handle);
}

/**
 * https://gist.github.com/joel-james/3a6201861f12a7acf4f2
 * Check if a given string is a valid UUID
 *
 * @param   string  $uuid   The string to check
 * @return  boolean
 */
function isValidUuid( $uuid ) {

    if (!is_string($uuid) || (preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $uuid) !== 1)) {
        return false;
    }

    return true;
}
