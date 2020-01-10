# require 'lita/acapters/idobata/callback'

require "lita/idobata/version"
require 'ld-eventsource'
require 'faraday'
require 'json'

module Lita
  module Adapters
    class Idobata < Adapter
      class Connector
        attr_reader :robot, :client, :roster

        def initialize(robot, api_token: nil, idobata_url: nil, debug: false)
          @robot       = robot
          @api_token   = api_token
          @idobata_url = idobata_url
          @debug       = debug
          Lita.logger.info("Enabling log.") if @debug
        end

        def connect
          raise "api_token is requeired." unless @api_token

          SSE::Client.new "#{@idobata_url}/api/stream?access_token=#{@api_token}", logger: ::Logger.new($stdout) do |stream|
            bot_id = nil

            stream.on_event do |ev|
              case ev.type
              when :seed
                seed   = JSON.parse(ev.data, symbolize_names: true)
                bot_id = seed[:records][:bot][:id]
              when :event
                event = JSON.parse(ev.data, symbolize_names: true)

                next unless event[:type] == 'message:created'

                message = event[:data][:message]

                next if message[:sender_type] == 'bot' && message[:sender_id] == bot_id

                user    = find_user(*message.values_at(:sender_id, :sender_name, :sender_type))
                source  = Source.new(user: user, room: message[:room_id].to_s)
                # `message["body_plain"]` is nil on image upload
                message = Message.new(robot, message[:body_plain].to_s, source)

                robot.receive message
              end
            end
          end
        end

        def message(target, strings)
          http_client.post '/api/messages', {
            'message[room_id]' => target.room,
            'message[source]' => strings.join("\n")
          }
        end

        def rooms
        end

        def shut_down
        end

      private

        def find_user(id, name, type)
          # hook has no personality, it's only a machine
          return User.new(id, name: name) if type == 'HookEndpoint'

          User.find_by_id(id) || User.create(id, name: name)
        end

        def http_client
          @conn ||= Faraday.new(url: @idobata_url) do |faraday|
            faraday.request  :url_encoded             # form-encode POST params
            faraday.response :logger                  # log requests to STDOUT
            faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP

            faraday.headers['Authorization'] = "Bearer #{@api_token}"
            faraday.headers['User-Agent']    = "lita-idobata / v#{Lita::Idobata::VERSION}"
          end
        end
      end
    end
  end
end
