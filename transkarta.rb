require "capybara"
require "capybara/dsl"
require "capybara-webkit"
require "pry"
require "net/http"
require "net/https"
require "mini_magick"
require "base64"
require "json"

Capybara.run_server = false
Capybara.current_driver = :webkit

Capybara::Webkit.configure do |config|
  config.allow_unknown_urls
end

class Transkarta
  include Capybara::DSL

  def perform
    File.delete("page.png") if File.exist?("page.png")
    File.delete("captcha.png") if File.exist?("captcha.png")

    puts "Looking for captcha..."

    visit "http://81.23.146.8"
    find("input").click
    # binding.pry
    # return
    file_name = "page.png"
    save_screenshot(file_name)

    image = MiniMagick::Image.open("page.png")
    image.crop "200x60+100+100"
    image.write("captcha.png")

    puts "Parsing captcha..."

    uri = URI("http://api.anti-captcha.com/createTask")
    image_base64 = Base64.encode64(File.open("captcha.png", "rb").read).gsub("\n", "")

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {
      "clientKey" => "a69944553300347c8548c21f9d02ecfe",
      "task" => {
        "type" => "ImageToTextTask",
        "body" => image_base64,
        "phrase" => false,
        "case" => false,
        "numeric" => 1,
        "math" => false,
        "minLength" => 4,
        "maxLength" => 4
      }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    task_id = JSON.parse(response.body)["taskId"]

    loop do
      sleep 1
      uri = URI("https://api.anti-captcha.com/getTaskResult")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = {
        "clientKey" => "a69944553300347c8548c21f9d02ecfe",
        "taskId" => task_id
      }.to_json

      https = Net::HTTP.new(uri.hostname, uri.port)
      https.use_ssl = true
      response = https.request(req)
      @response_body = JSON.parse(response.body)

      break if @response_body["status"] == "ready"
    end

    puts "Getting card data..."

    cardnum = "0656599393"
    checkcode = @response_body["solution"]["text"]
    event_validation = find("#__EVENTVALIDATION", visible: false).value
    view_state = find("#__VIEWSTATE", visible: false).value

    uri = URI("http://81.23.146.8/default.aspx")
    res = Net::HTTP.post_form(uri,
      "cardnum" => cardnum,
      "checkcode" => checkcode,
      "__EVENTVALIDATION" => event_validation,
      "__VIEWSTATE" => view_state
    )

    puts res.body
  end
end

Transkarta.new.perform
