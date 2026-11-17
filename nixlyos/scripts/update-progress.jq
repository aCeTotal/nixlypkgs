# Nix log to progress events.
def plain: gsub("\u001b\\[[0-9;]*m"; "");

foreach (inputs | ltrimstr("@nix ") | try fromjson catch empty) as $e ({};
  if $e.action != "start" then .
  elif $e.type | IN(103, 104, 105) then .[$e.id | tostring] = $e.type
  elif $e.type == 0 and ($e.text | startswith("evaluating derivation"))
  then .[$e.id | tostring] = "eval" else . end;
  .[$e.id | tostring] as $t
  | if $e.action == "stop" and $t == "eval" then "evaluated"
    elif $e.action == "start" and $e.type == 105 then "start\t\($e.id)\t\($e.fields[0])"
    elif $e.action == "stop" and $t == 105 then "stop\t\($e.id)"
    elif $e.action == "result" and $e.type == 105 and ($t == 103 or $t == 104)
    then "count\t\($t)\t\($e.fields[0])\t\($e.fields[1])"
    elif $e.action == "result" and $e.type == 106 and $e.fields[0] == 101
    then "bytes\t\($e.fields[1])"
    elif $e.action == "msg" and $e.level == 0
    then $e.msg | plain
      | (capture("Cannot build '(?<d>[^']+\\.drv)'[\\s\\S]*Reason: builder failed")
         // capture("builder for '(?<d>[^']+\\.drv)' failed"))
      | "failed\t\(.d)"
    else empty end)
