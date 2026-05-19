function godot
  nohup ~/Applications/godot/editor $argv >/dev/null 2>&1 </dev/null &
  disown
end
