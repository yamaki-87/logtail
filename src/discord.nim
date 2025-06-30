import httpclient, json, strformat, asyncdispatch, logging, strutils
import utils

let headers = newHttpHeaders()
headers.add("Content-Type", "application/json")
let successCode = "204"

proc sendDiscordMessage*(webhookUrl: string, content: string): Future[
    void] {.async.} =
    let client = newAsyncHttpClient()
    client.headers = headers
    let payload = %*{"content": content}
    logging.info "Sending message to Discord start"
    try:
        let res = await client.post(webhookUrl, body = payload.pretty(), nil)
        let status = res.status
        if isStringEmpty(status):
            logging.error "Received empty status from Discord."
            return
        let statusCode = status.strip().substr(0, 2)
        if statusCode != successCode:
            logging.error "Failed to send message to Discord. Status: ", status
        else:
            logging.info "Message sent successfully."

    except HttpRequestError as e:
        logging.error "Failed to send message to Discord: ", e.msg
    except Exception as e:
        logging.error "An unexpected error occurred while sending message to Discord. Error: ", e.msg
    finally:
        client.close()
