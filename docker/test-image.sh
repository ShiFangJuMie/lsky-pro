#!/bin/sh
set -eu

image=${1:?Usage: sh docker/test-image.sh IMAGE}
suffix="$$-$(date +%s)"
container="lsky-php-test-$suffix"
volume="lsky-php-test-$suffix"
incomplete="lsky-php-incomplete-$suffix"
cleanup() {
    if [ "$?" -ne 0 ]; then docker logs "$container" >&2 2>/dev/null || true; fi
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker volume rm "$volume" "$incomplete" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

docker volume create "$volume" >/dev/null
docker volume create "$incomplete" >/dev/null
docker run -d --name "$container" --network none --memory 512m --cpus 1 \
    --pids-limit 128 --mount "type=volume,src=$volume,dst=/var/www/html" "$image" >/dev/null

# No application bootstrap: replace the isolated volume's index with a PHP/Apache probe.
attempt=0
until docker exec "$container" test -s /var/run/apache2/apache2.pid 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then docker logs "$container"; exit 1; fi
    sleep 1
done
docker exec -i "$container" sh -c 'cat > /var/www/html/public/index.php' <<'PHP'
<?php
header('Content-Type: application/json');
$image = new Imagick();
$image->newImage(2, 3, 'white', 'png');
$decoded = new Imagick();
$decoded->readImageBlob($image->getImageBlob());
echo json_encode([
    'version' => PHP_VERSION_ID,
    'sapi' => PHP_SAPI,
    'image' => [$decoded->getImageWidth(), $decoded->getImageHeight()],
    'authorization' => $_SERVER['HTTP_AUTHORIZATION'] ?? null,
]);
PHP
docker exec "$container" sh -c 'printf preserved > /var/www/html/runtime-test-sentinel; chmod 640 /var/www/html/runtime-test-sentinel; printf test-image > /var/www/html/storage/app/uploads/runtime-test.txt'
docker restart "$container" >/dev/null

docker exec -i "$container" php <<'PHP'
<?php
function request(string $scheme, int $port, string $path): string
{
    $context = stream_context_create(['ssl' => ['verify_peer' => false, 'verify_peer_name' => false]]);
    for ($attempt = 0; $attempt < 30; $attempt++) {
        $socket = @stream_socket_client("$scheme://127.0.0.1:$port", $errno, $error, 1, STREAM_CLIENT_CONNECT, $context);
        if ($socket) {
            stream_set_timeout($socket, 5);
            fwrite($socket, "GET $path HTTP/1.0\r\nHost: localhost\r\nAuthorization: Bearer fixture\r\n\r\n");
            $response = stream_get_contents($socket);
            fclose($socket);
            if (str_starts_with($response, 'HTTP/1.1 200') || str_starts_with($response, 'HTTP/1.0 200')) {
                return explode("\r\n\r\n", $response, 2)[1];
            }
            throw new RuntimeException('Unexpected HTTP response: '.strtok($response, "\r\n"));
        }
        usleep(200000);
    }
    throw new RuntimeException('Apache did not start');
}
foreach ([['tcp', 8089], ['tls', 8088]] as [$scheme, $port]) {
    $result = json_decode(request($scheme, $port, '/runtime-check'), true, 512, JSON_THROW_ON_ERROR);
    if ($result['version'] < 80235 || $result['version'] >= 80300 || $result['sapi'] !== 'apache2handler'
        || $result['image'] !== [2, 3] || $result['authorization'] !== 'Bearer fixture') {
        throw new RuntimeException('PHP/Apache/image/authentication-header check failed');
    }
    echo "$scheme: ".json_encode($result)."\n";
}
if (request('tcp', 8089, '/i/runtime-test.txt') !== 'test-image'
    || file_get_contents('/var/www/html/runtime-test-sentinel') !== 'preserved'
    || fileowner('/var/www/html/runtime-test-sentinel') !== 0
    || (fileperms('/var/www/html/runtime-test-sentinel') & 0777) !== 0640) {
    throw new RuntimeException('Existing volume or upload symlink was not preserved');
}
PHP

docker rm -f "$container" >/dev/null
docker run --rm --network none --memory 128m --cpus 1 --pids-limit 32 \
    --mount "type=volume,src=$volume,dst=/var/www/html" --entrypoint php "$image" -r '
    $path = "/var/www/html/vendor/composer/installed.json";
    $installed = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
    foreach ($installed["packages"] as &$package) {
        if ($package["name"] === "laravel/framework") { $package["require"]["php"] = "<8.2"; }
    }
    file_put_contents($path, json_encode($installed, JSON_THROW_ON_ERROR));'
if output=$(docker run --name "$container" --network none --memory 256m --cpus 1 --pids-limit 64 \
    --mount "type=volume,src=$volume,dst=/var/www/html" "$image" apachectl -t 2>&1); then
    echo 'FAIL: incompatible existing application dependencies were accepted' >&2
    exit 1
fi
case "$output" in *php*failed*) ;; *) printf '%s\n' "$output"; exit 1 ;; esac
docker rm -f "$container" >/dev/null

docker run --rm --network none --memory 128m --cpus 1 --pids-limit 32 \
    --mount "type=volume,src=$incomplete,dst=/var/www/html" \
    --entrypoint sh "$image" -c 'printf preserved > /var/www/html/sentinel'
if output=$(docker run --name "$container" --network none --memory 256m --cpus 1 --pids-limit 64 \
    --mount "type=volume,src=$incomplete,dst=/var/www/html" "$image" 2>&1); then
    echo 'FAIL: incomplete application volume was accepted' >&2
    exit 1
else
    status=$?
    printf '%s\n' "$output"
    [ "$status" -eq 1 ] || exit "$status"
    case "$output" in *'refusing to overwrite it.'*) ;; *) exit 1 ;; esac
fi
docker run --rm --network none --memory 128m --cpus 1 --pids-limit 32 \
    --mount "type=volume,src=$incomplete,dst=/var/www/html" \
    --entrypoint sh "$image" -c 'test "$(cat /var/www/html/sentinel)" = preserved && test ! -e /var/www/html/public/index.php'
echo 'PASS: patched Apache PHP, HTTPS, Imagick, rewrite/auth header, uploads, restart preservation, incompatible-dependency and incomplete-volume guards'
