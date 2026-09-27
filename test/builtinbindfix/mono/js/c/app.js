const express = require("express");
const app = express();
function handler(req, res) { res.send("x"); }
function routes() { app.has("/x", handler); }
function lookupMap(m, k) { return m.has(k); }
function first(list) { return list.shift(); }
module.exports = { routes, lookupMap, first };
