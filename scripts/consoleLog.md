ubuntu@vps-1f1bdee5:~/kotapero$ docker-compose up -d
Traceback (most recent call last):
  File "/usr/lib/python3/dist-packages/urllib3/connectionpool.py", line 787, in urlopen
    response = self._make_request(
        conn,
    ...<10 lines>...
        **response_kw,
    )
  File "/usr/lib/python3/dist-packages/urllib3/connectionpool.py", line 493, in _make_request
    conn.request(
    ~~~~~~~~~~~~^
        method,
        ^^^^^^^
    ...<6 lines>...
        enforce_content_length=enforce_content_length,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/usr/lib/python3/dist-packages/urllib3/connection.py", line 445, in request
    self.endheaders()
    ~~~~~~~~~~~~~~~^^
  File "/usr/lib/python3.13/http/client.py", line 1353, in endheaders
    self._send_output(message_body, encode_chunked=encode_chunked)
    ~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/http/client.py", line 1113, in _send_output
    self.send(msg)
    ~~~~~~~~~^^^^^
  File "/usr/lib/python3.13/http/client.py", line 1057, in send
    self.connect()
    ~~~~~~~~~~~~^^
  File "/usr/lib/python3/dist-packages/docker/transport/unixconn.py", line 26, in connect
    sock.connect(self.unix_socket)
    ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^
PermissionError: [Errno 13] Permission denied

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/python3/dist-packages/requests/adapters.py", line 667, in send
    resp = conn.urlopen(
        method=request.method,
    ...<9 lines>...
        chunked=chunked,
    )
  File "/usr/lib/python3/dist-packages/urllib3/connectionpool.py", line 841, in urlopen
    retries = retries.increment(
        method, url, error=new_e, _pool=self, _stacktrace=sys.exc_info()[2]
    )
  File "/usr/lib/python3/dist-packages/urllib3/util/retry.py", line 474, in increment
    raise reraise(type(error), error, _stacktrace)
          ~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/urllib3/util/util.py", line 38, in reraise
    raise value.with_traceback(tb)
  File "/usr/lib/python3/dist-packages/urllib3/connectionpool.py", line 787, in urlopen
    response = self._make_request(
        conn,
    ...<10 lines>...
        **response_kw,
    )
  File "/usr/lib/python3/dist-packages/urllib3/connectionpool.py", line 493, in _make_request
    conn.request(
    ~~~~~~~~~~~~^
        method,
        ^^^^^^^
    ...<6 lines>...
        enforce_content_length=enforce_content_length,
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    )
    ^
  File "/usr/lib/python3/dist-packages/urllib3/connection.py", line 445, in request
    self.endheaders()
    ~~~~~~~~~~~~~~~^^
  File "/usr/lib/python3.13/http/client.py", line 1353, in endheaders
    self._send_output(message_body, encode_chunked=encode_chunked)
    ~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/http/client.py", line 1113, in _send_output
    self.send(msg)
    ~~~~~~~~~^^^^^
  File "/usr/lib/python3.13/http/client.py", line 1057, in send
    self.connect()
    ~~~~~~~~~~~~^^
  File "/usr/lib/python3/dist-packages/docker/transport/unixconn.py", line 26, in connect
    sock.connect(self.unix_socket)
    ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^
urllib3.exceptions.ProtocolError: ('Connection aborted.', PermissionError(13, 'Permission denied'))

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/python3/dist-packages/docker/api/client.py", line 223, in _retrieve_server_version
    return self.version(api_version=False)["ApiVersion"]
           ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/docker/api/daemon.py", line 181, in version
    return self._result(self._get(url), json=True)
                        ~~~~~~~~~^^^^^
  File "/usr/lib/python3/dist-packages/docker/utils/decorators.py", line 44, in inner
    return f(self, *args, **kwargs)
  File "/usr/lib/python3/dist-packages/docker/api/client.py", line 246, in _get
    return self.get(url, **self._set_request_timeout(kwargs))
           ~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/requests/sessions.py", line 602, in get
    return self.request("GET", url, **kwargs)
           ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/requests/sessions.py", line 589, in request
    resp = self.send(prep, **send_kwargs)
  File "/usr/lib/python3/dist-packages/requests/sessions.py", line 703, in send
    r = adapter.send(request, **kwargs)
  File "/usr/lib/python3/dist-packages/requests/adapters.py", line 682, in send
    raise ConnectionError(err, request=request)
requests.exceptions.ConnectionError: ('Connection aborted.', PermissionError(13, 'Permission denied'))

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/usr/bin/docker-compose", line 33, in <module>
    sys.exit(load_entry_point('docker-compose==1.29.2', 'console_scripts', 'docker-compose')())
             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^
  File "/usr/lib/python3/dist-packages/compose/cli/main.py", line 81, in main
    command_func()
    ~~~~~~~~~~~~^^
  File "/usr/lib/python3/dist-packages/compose/cli/main.py", line 200, in perform_command
    project = project_from_options('.', options)
  File "/usr/lib/python3/dist-packages/compose/cli/command.py", line 60, in project_from_options
    return get_project(
        project_dir,
    ...<8 lines>...
        enabled_profiles=get_profiles_from_options(options, environment)
    )
  File "/usr/lib/python3/dist-packages/compose/cli/command.py", line 152, in get_project
    client = get_client(
        verbose=verbose, version=api_version, context=context, environment=environment
    )
  File "/usr/lib/python3/dist-packages/compose/cli/docker_client.py", line 41, in get_client
    client = docker_client(
        version=version, context=context,
        environment=environment
    )
  File "/usr/lib/python3/dist-packages/compose/cli/docker_client.py", line 148, in docker_client
    client = APIClient(use_ssh_client=not use_paramiko_ssh, **kwargs)
  File "/usr/lib/python3/dist-packages/docker/api/client.py", line 207, in __init__
    self._version = self._retrieve_server_version()
                    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^
  File "/usr/lib/python3/dist-packages/docker/api/client.py", line 230, in _retrieve_server_version
    raise DockerException(
        f'Error while fetching server API version: {e}'
    ) from e
docker.errors.DockerException: Error while fetching server API version: ('Connection aborted.', PermissionError(13, 'Permission denied'))