# IO_Uring Zig app

# Build

On Linux:
```
$ zig build run
```

On macOS:
```
$ docker-compose run -it --rm web sh
$ /deps/local/zig build run
```

Make requests:
```
# For macOS:
$ docker-compose docker-compose exec -it web sh
$ curl localhost:8080
```
