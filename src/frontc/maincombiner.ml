module E = Errormsg
open Pretty

exception ParseError of string

(* parse, and apply patching *)
let rec parse_to_cabs fname =
  let cabs = 
    try
      ignore (E.log "Frontc is parsing %s\n" fname);
      flush !E.logChannel;
      let file = open_in fname in
      E.hadErrors := false;
      let lexbuf: Lexing.lexbuf = Clexer.init fname file in
      let cabs =
        Stats.time "parse"
          (Cparser.file Clexer.initial) lexbuf in
      close_in file;
      ignore (E.log "Frontc finished parsing %s\n" fname);
      cabs
    with (Sys_error msg) -> begin
      ignore (E.log "Cannot open %s : %s\n" fname msg);
      raise (ParseError("Cannot open " ^ fname ^ ": " ^ msg ^ "\n"))
    end
    | Parsing.Parse_error -> begin
        ignore (E.log "Parsing error\n");
        raise (ParseError("Parse error"))
    end
    | e -> begin
        ignore (E.log "Caught %s while parsing\n" (Printexc.to_string e));
        raise e
    end
  in
  cabs


let combine (files: string list) (out: string) =
  let combined_cabs = 
    let list_of_parsed_files =
      List.map (fun file_name -> parse_to_cabs file_name) files in
    Combine.combine list_of_parsed_files
  in
  try
    let o = open_out out in
    output_string o ("/* Generated by Frontc */\n");
    Stats.time "printCombine" (Cprint.print o) combined_cabs;
    close_out o
  with (Sys_error msg) as e -> begin
    ignore (E.log "Cannot open %s : %s\n" out msg);
    raise e
  end

        
(***** MAIN *****)  
let rec theMain () =
  let usageMsg = "Usage: combiner [options] source-files" in
  let files : string list ref = ref [] in
  let recordFile fname = files := fname :: (!files) in
  let outputFile = ref "" in
  let openLog lfile =
    if !E.verboseFlag then
      ignore (Printf.printf "Setting log file to %s\n" lfile);
    try E.logChannel := open_out lfile with _ ->
      raise (Arg.Bad "Cannot open log file") in
  let setDebugFlag v name = 
    E.debugFlag := v; if v then Pretty.flushOften := true
  in
  (*********** COMMAND LINE ARGUMENTS *****************)
  let argDescr = [
    "-verbose", Arg.Unit (fun _ -> E.verboseFlag := true),
                "turn of verbose mode";
    "-debug", Arg.String (setDebugFlag true),
                     "<xxx> turns on debugging flag xxx";
    "-flush", Arg.Unit (fun _ -> Pretty.flushOften := true),
                     "Flush the output streams often (aids debugging)" ;
    "-log", Arg.String openLog, "the name of the log file";
    "-o", Arg.String (fun s -> outputFile := s),
                     "output file for the combiner";
    "-msvc", Arg.Unit (fun _ -> Cprint.msvcMode := true),
             "Produce MSVC output. Default is GNU";
    "-noPrintLn", Arg.Unit (fun _ -> Cprint.printLn := false),
               "don't output #line directives";
    "-commPrintLn", Arg.Unit (fun _ -> Cprint.printLnComment := true),
               "output #line directives in comments";
  ] in
  begin
    Stats.reset ();
    Arg.parse argDescr recordFile usageMsg;
    files := List.rev !files;
    if !outputFile = "" then 
      E.s (E.bug "No output file was specified");
    combine !files !outputFile
  end
;;
                                        (* Define a wrapper for main to 
                                         * intercept the exit *)
let failed = ref false 
let main () = 
  let term = 
    try 
      theMain (); 
      fun () -> exit (if !failed then 1 else 0)
    with e ->  
      (fun () -> 
        print_string ("Uncaught exception: " ^ (Printexc.to_string e)
                      ^ "\n");
        Stats.print stderr "Timings:\n";
        exit 2)
  in
  begin
    if !E.verboseFlag then
      Stats.print stderr "Timings:\n";
    term ()
  end
;;

Printexc.catch main ()
;;
