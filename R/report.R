
#' Generate report from `ssr` tags.
#'
#' @param path Path to package for which report is to be generated
#' @param view If `TRUE` (default), a html-formatted version of the report is
#' opened in default system browser. If `FALSE`, the return object includes the
#' name of a `html`-rendered version of the report in an attribute named 'file'.
#' @param branch By default a report will be generated from the current branch
#' as set on the local git repository; this parameter can be used to specify any
#' alternative branch.
#' @return (invisibly) Markdown-formatted lines used to generate the final html
#' document.
#' @family report
#' @export
#' @examples
#' \dontrun{
#' path <- srr_stats_pkg_skeleton ()
#' srr_report (path)
#' }
srr_report <- function (path = ".", branch = "", view = TRUE) {

    requireNamespace ("rmarkdown")

    if (path == ".")
        path <- here::here ()

    remote <- get_git_remote (path)
    branch <- get_git_branch (path, branch)

    msgs <- get_all_msgs (path)
    std_txt <- get_stds_txt (msgs)

    tags <- c ("srrstats", "srrstatsNA", "srrstatsTODO")
    md_lines <- lapply (tags, function (tag) {
                            res <- one_tag_to_markdown (msgs,
                                                        remote,
                                                        tag,
                                                        branch,
                                                        std_txt)
                            if (length (res) > 0) {

                                dirs <- attr (res, "dirs")
                                dirs [dirs == "."] <- "root"

                                md <- res
                                res <- NULL
                                for (d in unique (dirs)) {

                                    res <- c (res,
                                              "",
                                              paste0 ("### ", d, " directory"),
                                              "",
                                              unlist (md [which (dirs == d)]))
                                }

                                res <- c (paste0 ("## Standards with `",
                                                  tag,
                                                  "` tag"),
                                          "",
                                          res,
                                          "",
                                          "---",
                                          "")
                            }
                            return (res)
                        })
    md_lines <- unlist (md_lines)

    desc <- data.frame (read.dcf (file.path (path, "DESCRIPTION")))
    pkg <- desc$Package

    if (is.null (remote)) {
        md_title <- paste0 ("# srr report for ", pkg)
    } else {
        md_title <- paste0 ("# srr report for [",
                            pkg,
                           "](",
                           remote,
                           ")")
    }

    md_lines <- c (md_title,
                   "",
                   paste0 ("[Click here for full text of all standards](",
                           "https://ropenscilabs.github.io/",
                           "statistical-software-review-book/standards.html)"),
                   "",
                   md_lines)

    md_lines <- add_missing_stds (md_lines, std_txt)

    f <- tempfile (fileext = ".Rmd")
    # need explicit line break to html render
    writeLines (paste0 (md_lines, "\n"), con = f)
    out <- paste0 (tools::file_path_sans_ext (f), ".html")
    rmarkdown::render (input = f, output_file = out)

    u <- paste0 ("file://", out)
    if (view)
        utils::browseURL (u)
    else
        attr (md_lines, "file") <- out

    invisible (md_lines)
}

get_all_msgs <- function (path = ".") {

    flist <- list.files (file.path (path, "R"), full.names = TRUE)
    blocks <- lapply (flist, function (i) roxygen2::parse_file (i))
    names (blocks) <- flist
    blocks <- do.call (c, blocks)

    blocks <- collect_blocks (blocks, path)

    msgs <- collect_one_tag (path, blocks, tag = "srrstats")
    msgs_na <- collect_one_tag (path, blocks, tag = "srrstatsNA")
    msgs_todo <- collect_one_tag (path, blocks, tag = "srrstatsTODO")

    list (msgs = msgs,
          msgs_na = msgs_na,
          msgs_todo = msgs_todo)
}

#' Get text of actual standards contained in lists of standards messages
#'
#' @param msgs Result of 'get_all_msgs()' function
#' @noRd
get_stds_txt <- function (msgs) {

    s_msgs <- parse_std_refs (msgs$msgs)
    s_na <- parse_std_refs (msgs$msgs_na)
    #s_todo <- parse_std_refs (msgs$msgs_todo)
    cats_msg <- get_categories (s_msgs)
    cats_na <- get_categories (s_na)
    #cats_todo <- get_categories (s_todo)
    cats <- unique (c (cats_msg$category, cats_na$category))
    s <- get_standards_checklists (cats)
    ptn <- "^\\s?\\-\\s\\[\\s\\]\\s\\*\\*"
    s <- gsub (ptn, "", grep (ptn, s, value = TRUE))
    g <- regexpr ("\\*\\*", s)
    std_nums <- substring (s, 1, g - 1)
    std_txt <- gsub ("^\\*|\\*$", "",
                     substring (s, g + 3, nchar (s)))

    data.frame (std = std_nums,
                text = std_txt)
}

#' one_tag_to_markdown
#'
#' Convert all messages for one defined tag into multiple markdown-formatted
#' lines
#' @param m List of all messages, divided into the 3 categories of tags
#' @param std_txt Result of 'get_stds_txt' function
#' @noRd
one_tag_to_markdown <- function (m, remote, tag, branch, std_txt) {

    i <- match (tag, c ("srrstats", "srrstatsNA", "srrstatsTODO"))
    tag <- c ("msgs", "msgs_na", "msgs_todo") [i]
    m <- m [[tag]]

    files <- gsub ("^.*of file\\s\\[|\\]$", "", unlist (m))
    dirs <- vapply (strsplit (files, .Platform$file.sep),
                    function (i) i [1],
                    character (1))

    m <- vapply (m, function (i)
                 one_msg_to_markdown (i, remote, branch, std_txt),
                 character (1))

    ret <- strsplit (m, "\n")
    attr (ret, "dirs") <- dirs

    return (ret)
}

#' one_msg_to_markdown
#'
#' Convert single-entry character vector of one message into one
#' markdown-formatted line
#' @param m One message
#' @noRd
one_msg_to_markdown <- function (m, remote, branch, std_txt) {

    g <- gregexpr ("[A-Z]+[0-9]+\\.[0-9]([0-9]?)([a-z]?)", m)

    stds <- regmatches (m, g) [[1]]
    stds_g <- sort (stds [grep ("^G", stds)])
    stds_other <- sort (stds [!stds %in% stds_g])
    stds <- c (stds_g, stds_other)

    g <- gregexpr ("\\sline#[0-9]+", m)
    line_num <- NA_integer_
    if (any (g [[1]] > 0))
        line_num <- gsub ("\\sline#", "", regmatches (m, g) [[1]])

    fn <- NA_character_
    if (grepl ("\\sfunction\\s", m)) {
        g <- gregexpr ("\\sfunction\\s+\\'.*\\'", m)
        fn <- gsub ("^\\sfunction\\s+\\'|\\'$", "", regmatches (m, g) [[1]])
    }

    g <- gregexpr ("file\\s+\\[.*\\]$", m)
    file_name <- gsub ("file\\s+\\[|\\]$", "", regmatches (m, g) [[1]])

    if (!is.null (remote)) {

        remote_file <- paste0 (remote, "/blob/", branch, "/", file_name)
        if (!is.na (line_num))
            remote_file <- paste0 (remote_file, "#L", line_num)
    }

    stds <- stds [which (stds %in% std_txt$std)]
    index <- match (stds, std_txt$std)
    stds <- paste0 ("- ", std_txt$std [index],
                    " ", std_txt$text [index])

    br_open <- br_close <- ""
    if (!is.null (remote)) {
        br_open <- "["
        br_close <- "]"
    }

    msg <- paste0 ("Standards in ")
    if (!is.na (fn)) {
        msg <- paste0 (msg, "function '", fn, "'")
    }
    if (!is.na (line_num)) {
        msg <- paste0 (msg, " on line#", line_num)
    }
    msg <- paste0 (msg, " of file ", br_open, file_name, br_close)
    if (!is.null (remote))
        msg <- paste0 (msg, "(", remote_file, ")")
    msg <- paste0 (msg, ":")

    return (paste0 (c (msg, stds), collapse = "\n"))
}

#' Find any missing standards, first by getting all non-missing standards
#' from md_lines, then matching will std_txt which has all applicable stds
#'
#' @param md_lines Markdown-formatted list of standards addressed in package
#' @param std_txt A `data.frame` of all applicable standards, with columns of
#' `std` and `text`.
#' @return The `md_lines` input potentially modified through additional details
#' of missing standards
#' @noRd
add_missing_stds <- function (md_lines, std_txt) {

    md_stds <- grep ("^\\-\\s+[A-Z]+[0-9]+\\.[0-9]+([a-z]?)",
                     md_lines,
                     value = TRUE)
    g <- regexpr ("^\\-\\s+[A-Z]+[0-9]+\\.[0-9]+", md_stds)
    md_stds <- gsub ("^\\-\\s+", "", regmatches (md_stds, g))
    missing_stds <- std_txt$std [which (!std_txt$std %in% md_stds)]
    if (length (missing_stds) > 0) {

        md_lines <- c (md_lines,
                       "",
                       "## Missing Standards",
                       "",
                       "The following standards are missing:")

        cats <- get_categories (missing_stds)
        for (i in seq (nrow (cats))) {

            stds_i <- grep (paste0 ("^", cats$std_prefix [i]),
                            missing_stds,
                            value = TRUE)

            md_lines <- c (md_lines,
                           "",
                           paste0 (tools::toTitleCase (cats$category [i]),
                                   " standards:"),
                           "",
                           paste0 (stds_i, collapse = ", "),
                           "")
        }
    }

    return (md_lines)
}
