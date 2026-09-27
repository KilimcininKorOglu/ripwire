const q = require("../b/queue");
function head(items) { return q.shift(items); }
module.exports = { head };
