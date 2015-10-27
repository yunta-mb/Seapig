class @SeaPigServer


        constructor: (url)->
                @url = url
                @objects = {}
                @connect()


        connect: () ->
                @connected = false

                @socket = new WebSocket(@url,'SeaPig-0.0')

                @socket.onerror = (error) =>
                        console.log('Seapig socket error', error)
                        @socket.close()

                @socket.onclose = () =>
                        console.log('Seapig connection closed')
                        for object_id, object of @objects
                                object.valid = false
                        setTimeout((=>@connect()), 2000)

                @socket.onopen = () =>
                        console.log('Seapig connection opened')
                        @connected = true
                        for object_id, object of @objects
                                @socket.send(JSON.stringify(action: 'link', id: object_id, latest_known_version: object.version))

                @socket.onmessage = (event) =>
                        #console.log('Seapig message received', event)
                        data = JSON.parse(event.data)
                        switch data.action
                                when 'patch'
                                        @objects[data.id].patch(data) if @objects[data.id]
                                else
                                        console.log('Seapig received a stupid message', data)


        link: (object_id) ->
                @socket.send(JSON.stringify(action: 'link', id: object_id, latest_known_version: object.version)) if @connected
                @objects[object_id] = new SeaPigObject(object_id)


        unlink: (object_id) ->
                delete @objects[object_id]
                @socket.send(JSON.stringify(action: 'unlink', id: object_id)) if @connected



class SeaPigObject


        constructor: (id) ->
                @id = id
                @valid = false
                @version = null
                @object = {}
                @onchange = null


        patch: (data) ->
                if not data.old_version?
                        delete @object[key] for key, value of @object
                else if not _.isEqual(@version, data.old_version)
                        console.log("Seapig lost some updates, this shouldn't ever happen")
                jsonpatch.apply(@object, data.patch)
                @version = data.new_version
                @valid = true
                @onchange() if @onchange?
