const { ConnectionPool } = require("./pool");
function jsTrueLocal(key) { const pool = new ConnectionPool(); return pool.get(key); }
module.exports = { jsTrueLocal };
