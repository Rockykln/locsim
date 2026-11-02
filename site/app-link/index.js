const TARGET = "https://locsim.rockykln.com";

export default {
  fetch(request) {
    // Keep the language path (/de/) but drop everything else from the request.
    const path = /^\/de(\/|$)/.test(new URL(request.url).pathname) ? "/de/" : "/";
    return new Response(null, {
      status: 302,
      headers: { Location: TARGET + path, "Cache-Control": "no-store" },
    });
  },
};
