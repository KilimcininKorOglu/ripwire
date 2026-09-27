def rb_true_local(key)
  pool = RbPool.new
  pool.fetch(key)
end
