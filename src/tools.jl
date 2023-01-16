const SWAGGER_UI_IMAGE = "swaggerapi/swagger-ui"

docker_cmd(; use_sudo::Bool=false) = use_sudo ? `sudo docker` : `docker`

function stop_swagger_ui(; use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    find_cmd = `$docker ps -a -q -f ancestor=$SWAGGER_UI_IMAGE`
    container_id = strip(String(read(find_cmd)))
    
    if !isempty(container_id)
        stop_cmd = `$docker stop $container_id`
        stop_res = strip(String(read(stop_cmd)))

        if stop_res == container_id
            @debug("Stopped Swagger UI container")
        elseif isempty(stop_res)
            @debug("Swagger UI container not running")
        else
            @error("Failed to stop Swagger UI container: $stop_res")
            return false
        end

        container_id = strip(String(read(find_cmd)))
        if !isempty(container_id)
            rm_cmd = `$docker rm $container_id`
            rm_res = strip(String(read(rm_cmd)))

            if rm_res == container_id
                @debug("Removed Swagger UI container")
            elseif isempty(rm_res)
                @debug("Swagger UI container not found")
            else
                @error("Failed to remove Swagger UI container: $rm_res")
                return false
            end
        end

        return true
    else
        @debug("Swagger UI container not found")
    end

    return false
end

function swagger_ui(spec::String; port::Int=8080, use_sudo::Bool=false)
    docker = docker_cmd(; use_sudo=use_sudo)
    stop_swagger_ui(; use_sudo=use_sudo)
    cmd = `$docker run -d --rm -p $port:8080 -e SWAGGER_JSON=/tmp/spec.json -v $spec:/tmp/spec.json $SWAGGER_UI_IMAGE`
    run(cmd)
    return "http://localhost:$port"
end
