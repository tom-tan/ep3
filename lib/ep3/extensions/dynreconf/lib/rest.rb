require 'json'
require 'net/http'

def get_request(endpoint)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    headers = { 'Content-Type' => 'application/json' }
    response = http.get(uri.path, headers)
  
    if response.code != '200'
      ret = {
        message: 'Error in get_request',
        file: __FILE__,
        line: __LINE__,
        code: response.code.to_i,
        endpoint: endpoint,
        body: JSON.load(response.body),
      }
      raise JSON.dump(ret)
    end
  
    JSON.load(response.body)
    # {
    #   delete_id: del-xxx,
    #   request_id: xxx,
    #   done: false
    # }
end
  
def post_request(endpoint, params)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    headers = { 'Content-Type' => 'application/json' }
    response = http.post(uri.path, JSON.dump(params), headers)
    
    if response.code != '201'
        ret = {
            message: 'Error in post_request',
            file: __FILE__,
            line: __LINE__,
            code: response.code.to_i,
            endpoint: endpoint,
            parameter: params,
            body: JSON.load(response.body),
        }
        raise JSON.dump(ret)
    end

    JSON.load(response.body)
    # {
    #   req_id: xxx
    # }
end

def poll(endpoint, timeout)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    headers = { 'Content-Type' => 'application/json' }
    start = Time.now
    json = nil
    until Time.now-start > timeout do
        response = http.get(uri, headers)
        json = JSON.load(response.body)
        yield response.code.to_i, json
        sleep 10
    end
end
