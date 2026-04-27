export async function http_post_echo_js(prefix, value) {
    const response = await fetch('{{ env_var("JS_UDF_HTTP_BASE_URL", "http://127.0.0.1:18080") }}/echo', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ prefix, value }),
    });
    const data = await response.json();
    return data.result;
}
