$enc = New-Object System.Text.UTF8Encoding($false)
$B1 = [char]0x00B1   # plus-minus
$B7 = [char]0x00B7   # middot
$D3 = [char]0x2013   # en dash
$D4 = [char]0x2014   # em dash
$AP = [char]0x0027   # apostrophe

# ===== s04.html =====
$p = 'c:\Users\lenovo\Desktop\Sarathi\sarathi-deck\s04.html'
$t = [IO.File]::ReadAllText($p, $enc)
# fix garbled middleware line from earlier bad edit
$t = $t.Replace('CORS, session, auth and CORS, session and auth middleware, then DRF views, then DRF views with SimpleJWT', 'CORS, session and auth middleware, then DRF views with SimpleJWT')
# soften unverified specifics
$t = $t.Replace('7 roles (super admin', 'role-based access (admin')
$t = $t.Replace('weighted scoring (ETA, distance, readiness)', 'weighted scoring (ETA and distance)')
$t = $t.Replace('route cache 30 s ' + $B1 + ' 10 s, Haversine fallback', 'route cache 30 s, Haversine fallback')
$t = $t.Replace('Docker ' + $B7 + ' AOF', 'Docker')
$t = $t.Replace('redis:7-alpine with AOF (appendfsync everysec). DB 1: route cache, latest GPS fixes, sessions, throttle counters. DB 2: Channels pub/sub. Jittered TTLs avoid thundering herds.', 'Runs in Docker. DB 1: route cache and latest GPS fixes. DB 2: Channels pub/sub layer.')
[IO.File]::WriteAllText($p, $t, $enc)

# ===== s09.html =====
$p = 'c:\Users\lenovo\Desktop\Sarathi\sarathi-deck\s09.html'
$t = [IO.File]::ReadAllText($p, $enc)
$old = '<p class="s u" style="--d:.1s">A driver' + $AP + 's GPS fix becomes a moving marker on the dispatcher' + $AP + 's map.</p>'
$new = '<p class="s u" style="--d:.1s">A driver' + $AP + 's GPS fix reaches the dispatcher' + $AP + 's map via REST save and fast polling ' + $D4 + ' WebSockets carry the alerts.</p>'
$t = $t.Replace($old, $new)
$t = $t.Replace('<b>Channel groups</b>', '<b>WebSocket alerts (not GPS)</b>')
$t = $t.Replace("['Django','filter $B7 save']", "['Django','15 m jitter filter']")
$t = $t.Replace("['post_save','signal']", "['PostgreSQL','point + breadcrumb']")
$t = $t.Replace("['Redis DB 2','channel layer']", "['Redis DB 1','latest-fix cache']")
$t = $t.Replace("['Consumer','user_ + org_']", "['Dashboard','polls every 4${D3}5 s']")
$t = $t.Replace("['Dashboard','marker moves']", "['Map marker','moves on the map']")
[IO.File]::WriteAllText($p, $t, $enc)

Write-Output 'SCRIPT OK'
