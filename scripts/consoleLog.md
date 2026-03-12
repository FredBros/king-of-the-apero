Build configuration: Emscripten 4.0.20, single-threaded, no GDExtension support. index.js:452:16
🚀 Exported Build detected. Using Production Server: kotapero.xyz index.js:452:16
✅ Nakama Client initialized: https://kotapero.xyz:443 index.js:452:16
=== Nakama : DEBUG === Sending request [ID: 1, Method: POST, Uri: https://kotapero.xyz:443/v2/account/authenticate/device?create=true&, Headers: { "Authorization": "Basic a2g2NlBoWW43N3ltTkJFeTo=" }, Body: {"id":"web_guest_2516599362"}, Timeout: 3, Retries: 3, Backoff base: 10 ms] index.js:452:16
ERROR: Condition "err != 0 && err != 1" is true. Returning: FAILED <anonymous code>:1:145535
   at: _process (core/io/stream_peer_gzip.cpp:115) <anonymous code>:1:145535
=== Nakama : DEBUG === Request 1 failed with result: 8, response code: 200 index.js:452:16
=== Nakama : DEBUG === Retrying request 1. Tries left: 2. Backoff: 9 ms index.js:452:16
ERROR: Condition "err != 0 && err != 1" is true. Returning: FAILED <anonymous code>:1:145535
   at: _process (core/io/stream_peer_gzip.cpp:115) <anonymous code>:1:145535
=== Nakama : DEBUG === Request 1 failed with result: 8, response code: 200 index.js:452:16
=== Nakama : DEBUG === Retrying request 1. Tries left: 1. Backoff: 95 ms index.js:452:16
Erreur dans les liens source : Error: JSON.parse: unexpected character at line 1 column 1 of the JSON data
Stack in the worker:parseSourceMapInput@resource://devtools/client/shared/vendor/source-map/lib/util.js:163:15
_factory@resource://devtools/client/shared/vendor/source-map/lib/source-map-consumer.js:1069:22
SourceMapConsumer@resource://devtools/client/shared/vendor/source-map/lib/source-map-consumer.js:26:12
_fetch@resource://devtools/client/shared/source-map-loader/utils/fetchSourceMap.js:83:19

URL de la ressource : https://kotapero.xyz/%3Canonymous%20code%3E
URL du lien source : installHook.js.map
ERROR: Condition "err != 0 && err != 1" is true. Returning: FAILED <anonymous code>:1:145535
   at: _process (core/io/stream_peer_gzip.cpp:115) <anonymous code>:1:145535
=== Nakama : DEBUG === Request 1 failed with result: 8, response code: 200 index.js:452:16
=== Nakama : DEBUG === Freeing request 1 index.js:452:16
❌ Auth Error: HTTPRequest failed! <anonymous code>:1:145535