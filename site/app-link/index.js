const TARGET = "https://locsim.rockykln.com";

export default {
  fetch(request) {
    // Keep the language path (/de/, /fr/, ...) but drop everything else from the request.
    const match = /^\/(de|fr|es|it|pt|nl)(\/|$)/.exec(new URL(request.url).pathname);
    const path = match ? `/${match[1]}/` : "/";
    return new Response(null, {
      status: 302,
      headers: { Location: TARGET + path, "Cache-Control": "no-store" },
    });
  },
};
