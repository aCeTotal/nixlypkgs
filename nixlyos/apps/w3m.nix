{ ... }:

{
  config.home-manager.sharedModules = [
    ({ pkgs, ... }: {
      home.packages = with pkgs; [ w3m ];

      # Main w3m config, stored in ~/.w3m/config rather than XDG.
      home.file.".w3m/config".text = ''
        # Charset
        display_charset UTF-8
        document_charset UTF-8
        system_charset UTF-8
        auto_detect 2

        # Display
        color 1
        ansi_color 1
        use_mouse 1
        clear_buffer 1
        decode_cte 1
        fold_textarea 1
        display_image 0
        pseudo_inlines 1
        tabstop 4
        indent_incr 2

        # Navigation
        nextpage_topline 1
        label_topline 1
        emacs_like_lineedit 1
        vi_prec_num 1

        # Cookies / cache
        use_cookie 1
        accept_cookie 1
        accept_bad_cookie 0
        cookie_avoid_wrong_number_of_dots ""
        show_cookie 0

        # Tabs
        open_tab_blank 1
        open_tab_dl_list 1
        close_tab_back 1

        # Forms
        confirm_qq 0
        target_self 1

        # Downloads land in PWD: 'a' prompts, 'D' shells out to wget.
        download_dir .
        decode_cte 1
        auto_uncompress 1

        # Editor / pager
        editor nvim

        # External commands, invoked with M, 2 M or 3 M.
        # 1 = xdg-open
        # 2 = wget into PWD
        # 3 = wl-copy
        extbrowser  sh -c 'xdg-open "%s" &'
        extbrowser2 sh -c 'wget --content-disposition -- "%s"'
        extbrowser3 sh -c 'echo -n "%s" | wl-copy'
        mailto_options 0

        # SSL
        ssl_verify_server 1
        ssl_ca_file /etc/ssl/certs/ca-certificates.crt

        # Search
        case_sensitive 0
        wrap_search 1
      '';

      # Vim-like keymap: Tab or C-n/C-p cycles links, Enter follows one.
      home.file.".w3m/keymap".text = ''
        # Movement
        keymap  j         MOVE_DOWN
        keymap  k         MOVE_UP
        keymap  h         MOVE_LEFT
        keymap  l         MOVE_RIGHT
        keymap  g         BEGIN
        keymap  G         END
        keymap  C-f       NEXT_PAGE
        keymap  C-b       PREV_PAGE
        keymap  C-d       NEXT_HALF_PAGE
        keymap  C-u       PREV_HALF_PAGE
        keymap  H         LINE_BEGIN
        keymap  L         LINE_END

        # Cycle through links
        keymap  TAB       NEXT_LINK
        keymap  C-n       NEXT_LINK
        keymap  ESC-TAB   PREV_LINK
        keymap  C-p       PREV_LINK

        # Follow link or submit form
        keymap  RET       GOTO_LINK
        keymap  SPC       NEXT_PAGE

        # History
        keymap  u         BACK
        keymap  C-h       HISTORY
        keymap  U         GOTO
        keymap  r         RELOAD
        keymap  R         RELOAD

        # In-page search
        keymap  /         SEARCH
        keymap  ?         SEARCH_BACK
        keymap  n         SEARCH_NEXT
        keymap  N         SEARCH_PREV

        # Tabs
        keymap  t         NEW_TAB
        keymap  T         TAB_LINK
        keymap  C-w       CLOSE_TAB
        keymap  ]         NEXT_TAB
        keymap  [         PREV_TAB
        keymap  }         NEXT_TAB
        keymap  {         PREV_TAB

        # Download and external
        # 'a' saves a link, prompting with PWD.
        keymap  a         SAVE_LINK
        # 's' saves the current page.
        keymap  s         SAVE
        # 'd' shows the download queue.
        keymap  d         DOWNLOAD_LIST
        # 'M' opens the page in xdg-open.
        keymap  M         EXTERN
        # '2 M' downloads with wget.
        # '3 M' copies the URL to the clipboard.

        # Bookmarks
        keymap  B         BOOKMARK
        keymap  M-b       ADD_BOOKMARK

        # Misc
        keymap  o         OPTIONS
        keymap  v         VIEW
        keymap  =         INFO
        keymap  C-l       REDRAW
        keymap  q         EXIT
        keymap  Q         EXIT
        keymap  :         COMMAND
        keymap  M-h       HELP

        # URL to clipboard
        keymap  y         PIPE_BUF
        keymap  Y         PIPE_SHELL
      '';

      # Mailcap: which program opens what.
      home.file.".w3m/mailcap".text = ''
        image/*;             swayimg %s
        video/*;             mpv %s
        audio/*;             mpv %s
        application/pdf;     zathura %s
      '';
    })
  ];
}
