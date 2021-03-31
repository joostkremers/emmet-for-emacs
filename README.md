[Emmet](https://emmet.io/) describes itself as "a plugin for many popular text editors which greatly improves HTML & CSS workflow". `emmet-for-emacs` is an implementation of Emmet in Emacs. It is a fork of [`emmet-mode`](https://github.com/smihica/emmet-mode), which is itself a fork of [zencoding-mode](https://github.com/rooney/zencoding).



## About zencoding-mode

[zencoding-mode](https://github.com/rooney/zencoding) is a minor mode providing support for Zen Coding by producing HTML from CSS-like selectors. See [README](https://github.com/rooney/zencoding/blob/master/README.md)

## About Emmet

Emmet makes writing HTML code easier by producing HTML from CSS-like selectors. For example, you can write a line like

    ul#name>li.item*2

and have it expanded to

```
  <ul id="name">
    <li class="item"></li>
    <li class="item"></li>
  </ul>
```

`emmet-for-emacs` supports [HTML](#html-abbreviations) and [CSS abbreviations](#css-abbreviations), and the [Goto Edit Point](#go-to-edit-point) action.

## Supported Emacs

`emmet` requires at least GNU Emacs versions from 26.1.

## Installation

You can install `emmet-for-emacs` by placing `emmet.el` in your `load-path`. It is advisable to byte-compile it. For example, if you placed `emmet.el` in `~/src/Elisp/emmet-for-emacs/`, add the following lines to your init.el or .emacs:

    (add-to-list 'load-path "~/src/Elisp/emmet-for-emacs")
    (require 'emmet)

You can enable `emmet-for-emacs` by running `M-x emmet-mode` manually, but you will probably want to add it to auto-load on your sgml modes:

    (add-hook 'sgml-mode-hook 'emmet-mode) ;; Auto-start on any markup modes
    (add-hook 'css-mode-hook  'emmet-mode) ;; enable Emmet's css abbreviation.

By default, inserted markup will be indented with indent-region, according to the buffer's mode.  To disable this, do:

    (setq-default emmet-indent-after-insert nil)

If you disable indent-region, you can set the default indent level thus:

    (setq-default emmet-indentation 2)

If you want the cursor to be positioned between first empty quotes after expanding:

    (setq-default emmet-move-cursor-between-quotes t)

Or if you don't want to move cursor after expanding:

    (setq-default emmet-move-cursor-after-expanding nil)

If you want to use emmet with react-js's JSX, you probably want emmet to expand 'className="..."' instead of 'class="..."':

    (setq-default emmet-expand-jsx-className? t)

If you want to customize self-closing tags style:

    (setq-default emmet-self-closing-tag-style " /")

    ;; only " /", "/" and "" are valid.
    ;; eg. <meta />, <meta/>, <meta>

All customisation options can be found in the customisation group `emmet`.


## Usage

Place point in a emmet snippet and press `C-j` to expand it (or alternatively,
alias your preferred keystroke to `M-x emmet-expand-line`) and you'll transform your snippet into the appropriate tag structure.

## HTML abbreviations

#### Basic tags

    a                        <a href=""></a>
    a.x                      <a class="x" href=""></a>
    a#q.x                    <a id="q" class="x" href=""></a>
    a#q.x.y.z                <a id="q" class="x y z" href=""></a>
    #q                       <div id="q">
                             </div>
    .x                       <div class="x">
                             </div>
    #q.x                     <div id="q" class="x">
                             </div>
    #q.x.y.z                 <div id="q" class="x y z">
                             </div>

#### Empty tags

    a/                       <a href=""/>
    a/.x                     <a class="x" href=""/>
    a/#q.x                   <a id="q" class="x" href=""/>
    a/#q.x.y.z               <a id="q" class="x y z" href=""/>

#### Self-closing tags

    input[type=text]         <input type="text" name="" value=""/>
    img                      <img src="" alt=""/>
    img>metadata/*2          <img src="" alt="">
                                 <metadata/>
                                 <metadata/>
                             </img>

#### Siblings

    a+b                      <a href=""></a>
                             <b></b>
    a+b+c                    <a href=""></a>
                             <b></b>
                             <c></c>
    a.x+b                    <a class="x" href=""></a>
                             <b></b>
    a#q.x+b                  <a id="q" class="x" href=""></a>
                             <b></b>
    a#q.x.y.z+b              <a id="q" class="x y z" href=""></a>
                             <b></b>
    a#q.x.y.z+b#p.l.m.n      <a id="q" class="x y z" href=""></a>
                             <b id="p" class="l m n"></b>

#### Tag expansion

    table+                   <table>
                                 <tr>
                                     <td>
                                     </td>
                                 </tr>
                             </table>
    dl+                      <dl>
                                 <dt></dt>
                                 <dd></dd>
                             </dl>
    ul+                      <ul>
                                 <li></li>
                             </ul>
    ul++ol+                  <ul>
                                 <li></li>
                             </ul>
                             <ol>
                                 <li></li>
                             </ol>
    ul#q.x.y[m=l]            <ul id="q" class="x y" m="l">
                                 <li></li>
                             </ul>

#### Parent > child

    a>b                      <a href=""><b></b></a>
    a>b>c                    <a href=""><b><c></c></b></a>
    a.x>b                    <a class="x" href=""><b></b></a>
    a#q.x>b                  <a id="q" class="x" href=""><b></b></a>
    a#q.x.y.z>b              <a id="q" class="x y z" href=""><b></b></a>
    a#q.x.y.z>b#p.l.m.n      <a id="q" class="x y z" href=""><b id="p" class="l m n"></b></a>
    #q>.x                    <div id="q">
                                 <div class="x">
                                 </div>
                             </div>
    a>b+c                    <a href="">
                                 <b></b>
                                 <c></c>
                             </a>
    a>b+c>d                  <a href="">
                                 <b></b>
                                 <c><d></d></c>
                             </a>

#### Climb-up

    a>b^c                    <a href=""><b></b></a><c></c>
    a>b>c^d                  <a href="">
                                 <b><c></c></b>
                                 <d></d>
                             </a>
    a>b>c^^d                 <a href=""><b><c></c></b></a>
                             <d></d>

#### Multiplication

    a*1                      <a href=""></a>
    a*2                      <a href=""></a>
                             <a href=""></a>
    a/*2                     <a href=""/>
                             <a href=""/>
    a*2+b*2                  <a href=""></a>
                             <a href=""></a>
                             <b></b>
                             <b></b>
    a*2>b*2                  <a href="">
                                 <b></b>
                                 <b></b>
                             </a>
                             <a href="">
                                 <b></b>
                                 <b></b>
                             </a>
    a>b*2                    <a href="">
                                 <b></b>
                                 <b></b>
                             </a>
    a#q.x>b#q.x*2            <a id="q" class="x" href="">
                                 <b id="q" class="x"></b>
                                 <b id="q" class="x"></b>
                             </a>
    a#q.x>b/#q.x*2           <a id="q" class="x" href="">
                                 <b id="q" class="x"/>
                                 <b id="q" class="x"/>
                             </a>

#### Item numbering

    ul>li.item$*3            <ul>
                                 <li class="item1"></li>
                                 <li class="item2"></li>
                                 <li class="item3"></li>
                             </ul>
    ul>li.item$$$*3          <ul>
                                 <li class="item001"></li>
                                 <li class="item002"></li>
                                 <li class="item003"></li>
                             </ul>
    ul>li.item$@-*3          <ul>
                                 <li class="item3"></li>
                                 <li class="item2"></li>
                                 <li class="item1"></li>
                             </ul>
    ul>li.item$@3*3          <ul>
                                 <li class="item3"></li>
                                 <li class="item4"></li>
                                 <li class="item5"></li>
                             </ul>
    ul>li.item$@-3*3         <ul>
                                 <li class="item5"></li>
                                 <li class="item4"></li>
                                 <li class="item3"></li>
                             </ul>
    a$b$@-/*5                <a1b5/>
                             <a2b4/>
                             <a3b3/>
                             <a4b2/>
                             <a5b1/>
    a.$*2>b.$$@-*3           <a class=\"1\" href="">
                                 <b class=\"03\"></b>
                                 <b class=\"02\"></b>
                                 <b class=\"01\"></b>
                             </a>
                             <a class=\"2\" href="">
                                 <b class=\"03\"></b>
                                 <b class=\"02\"></b>
                                 <b class=\"01\"></b>
                             </a>
    (div>(a#id$$*2)+b.c$@-3+c#d$)*2
                             <div>
                                 <a id=\"id01\" href=""></a>
                                 <a id=\"id02\" href=""></a>
                                 <b class=\"c4\"></b>
                                 <c id=\"d1\"></c>
                             </div>
                             <div>
                                 <a id=\"id01\" href=""></a>
                                 <a id=\"id02\" href=""></a>
                                 <b class=\"c3\"></b>
                                 <c id=\"d2\"></c>
                             </div>
    ul>li.c${price: 10\\$}*3 <ul>
                                 <li class=\"c1\">price: 10$</li>
                                 <li class=\"c2\">price: 10$</li>
                                 <li class=\"c3\">price: 10$</li>
                             </ul>

#### Properties

    b[x]                     <b x=""></b>
    b[x=]                    <b x=""></b>
    b[x=""]                  <b x=""></b>
    b[x=y]                   <b x="y"></b>
    b[x="y"]                 <b x="y"></b>
    b[x="()"]                <b x="()"></b>
    b[x m]                   <b x="" m=""></b>
    b[x= m=""]               <b x="" m=""></b>
    b[x=y m=l]               <b x="y" m="l"></b>
    b/[x=y m=l]              <b x="y" m="l"/>
    b#foo[x=y m=l]           <b id="foo" x="y" m="l"></b>
    b.foo[x=y m=l]           <b class="foo" x="y" m="l"></b>
    b#foo.bar.mu[x=y m=l]    <b id="foo" class="bar mu" x="y" m="l"></b>
    b/#foo.bar.mu[x=y m=l]   <b id="foo" class="bar mu" x="y" m="l"/>
    b[x=y]+b                 <b x="y"></b>
                             <b></b>
    b[x=y]+b[x=y]            <b x="y"></b>
                             <b x="y"></b>
    b[x=y]>b                 <b x="y"><b></b></b>
    b[x=y]>b[x=y]            <b x="y"><b x="y"></b></b>
    b[x=y]>b[x=y]+c[x=y]     <b x="y">
                                 <b x="y"></b>
                                 <c x="y"></c>
                             </b>

#### Parentheses

    (a)                      <a href=""></a>
    (a)+(b)                  <a href=""></a>
                             <b></b>
    a>(b)                    <a href=""><b></b></a>
    (a>b)>c                  <a href=""><b></b></a>
    (a>b)+c                  <a href=""><b></b></a>
                             <c></c>
    z+(a>b)+c+k              <z></z>
                             <a href=""><b></b></a>
                             <c></c>
                             <k></k>
    (x)*2                    <x></x>
                             <x></x>
    ((x)*2)                  <x></x>
                             <x></x>
    ((x))*2                  <x></x>
                             <x></x>
    (x>b)*2                  <x><b></b></x>
                             <x><b></b></x>
    (x+b)*2                  <x></x>
                             <b></b>
                             <x></x>
                             <b></b>

#### Text

    a{Click me}              <a href="">Click me</a>
    a>{Click me}*2           <a href="">
                                 Click me
                                 Click me
                             </a>
    x{click}+b{here}         <x>click</x>
                             <b>here</b>
    span>{click}+b{here}     <span>
                                 click
                                 <b>here</b>
                             </span>
    p>{Click}+span{here}+{ to continue}
                             <p>
                                 Click
                                 <span>here</span>
                                  to continue
                             </p>
    p{Click}+span{here}+{ to continue}
                             <p>
                                 Click
                             </p>
                             <span>here</span>
                              to continue
    p{\{Escape brackets!\} and \\}
                             <p>{Escape brackets} and \</p>

#### Lorem-Ipsum generator

    lorem                    Diam, vulputate ut pharetra sit amet, aliquam id! Egestas sed tempus, urna et pharetra pharetra, massa massa ultricies mi, quis hendrerit dolor magna eget est lorem ipsum dolor sit amet!
    lorem5                   Hendrerit gravida rutrum quisque non?
    ipsum3                   Viverra ipsum nunc.
    p*3>lorem3               <p>Pellentesque elit eget?</p>
                             <p>Sed odio morbi?</p>
                             <p>Eget arcu dictum!</p>
    ul.list>ipsum3*3         <ul class=\"list\">
                                 Nam libero justo.
                                 Pellentesque habitant morbi?
                                 Enim blandit volutpat.
                             </ul>
    ul.list>ipsum3.itm*3     <ul class=\"list\">
                                 <div class=\"itm\">Urna condimentum mattis.</div> <!-- emmet-mode doesn't support implicit tag name resolver -->
                                 <div class=\"itm\">Sed turpis tincidunt.</div>
                                 <div class=\"itm\">Faucibus turpis in?</div>
                             </ul>
    ul.list>(li.itm>lorem3)*3
                             <ul class=\"list\">
                                 <li class=\"itm\">Est pellentesque elit.</li>
                                 <li class=\"itm\">In nulla posuere.</li>
                                 <li class=\"itm\">Felis eget nunc.</li>
                             </ul>

#### Filter: HTML with comments

    a.b|c                    <!-- .b -->
                             <a class="b" href=""></a>
                             <!-- /.b -->
    #a>.b|c                  <!-- #a -->
                             <div id="a">
                                 <!-- .b -->
                                 <div class="b">
                                 </div>
                                 <!-- /.b -->
                             </div>
                             <!-- /#a -->

#### Filter: HAML

    a|haml                   %a
    a#q.x.y.z|haml           %a#q.x.y.z
    a#q.x[x=y m=l]|haml      %a#q.x{:x => "y", :m => "l"}
    div|haml                 %div
    div.footer|haml          .footer
    .footer|haml             .footer
    p>{txt}+a[href=#]+br|haml  %p
                                 txt
                                 %a{:href => "#"}
                                 %br

#### Filter: Hiccup

    a|hic                    [:a]
    a#q.x.y.z|hic            [:a#q.x.y.z]
    a#q.x[x=y m=l]|hic       [:a#q.x {:x "y", :m "l"}]
    .footer|hic              [:div.footer]
    p>a[href=#]+br|hic       [:p
                                 [:a {:href "#"}]
                                 [:br]]
    #q>(a*2>b{x})+p>b|hic    [:div#q
                                 [:a [:b "x"]]
                                 [:a [:b "x"]]
                                 [:p
                                     [:b]]]

#### Filter: escape

    script[src=&quot;]|e     &lt;script src="&amp;quot;"&gt;
                             &lt;/script&gt;

#### Aliases

    html:5                   <!doctype html>
                             <html lang="en">
                               <head>
                                 <meta charset="UTF-8"/>
                                 <title>Document</title>
                               </head>
                               <body>
                               </body>
                             </html>

    html:xt                  <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
                             <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
                               <head>
                                 <meta http-equiv="Content-Type" content="text/html;charset=UTF-8"/>
                                 <title>Document</title>
                               </head>
                             </html>

    meta:vp                  <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0"/>


* See HTML section of [cheat-sheet](http://docs.emmet.io/cheat-sheet/) to find more aliases.


## CSS abbreviations

#### Basic Usage

    p1-2!+m10e+bd1#2s        padding: 1px 2px !important;
                             margin: 10em;
                             border: 1px #222 solid;

#### Keywords

    m                        margin: ;
    bg+                      background: #fff url() 0 0 no-repeat;
    c                        color: #000;

* See CSS section of [cheat-sheet](http://docs.emmet.io/cheat-sheet/) to find more keywords.

#### Values

separate each value by '-' or ' ';

    m1-2-3-4                 margin: 1px 2px 3px 4px;
    m1 2 3 4                 margin: 1px 2px 3px 4px;
    m1--2                    margin: 1px -2px;
    m1 -2                    margin: 1px -2px;

    bg+#c /back.png 10 20 repeat-x
                             background: #cccccc url(/back.png) 10px 20px repeat-x;

#### Multiple property definition

concatenate each property by '+';

    m10+p0                   margin: 10px;
                             padding: 0px;

    bg++c#0                  background: #fff url() 0 0 no-repeat;
                             color: #000;

    m0+p10+c#f+fw:b+w100+h20+bg#f00
                             margin: 0px;
                             padding: 10px;
                             color: #fff;
                             font-weight: bold;
                             width: 100px;
                             height: 20px;
                             background: #f00;

#### Value units

    m10                      margin: 10px;
    m1.5                     margin: 1.5em;
    m1.5ex                   margin: 1.5ex;
    m1.5x                    margin: 1.5ex;
    m10foo                   margin: 10foo;
    m10ex20em                margin: 10ex 20em;
    m10x20e                  margin: 10ex 20em;
    m10x-5                   margin: 10ex -5px;
    w100p                    width: 100%;
    m10p30e5x                margin: 10% 30em 5ex;

* Unit-aliases

        e                        em
        p                        %
        x                        ex
        r                        rem

#### Unitless property

    lh2                      line-height: 2;
    fw400                    font-weight: 400;

#### Color abbreviations

    c#3                      color: #333;
    bd5#0s                   border: 5px #000 solid; /* s: solid, t: dotted, n: none, h: hidden */
    bd5#20rgb                border: 5px rgb(32,32,32);
    bd5#20rgbt               border: 5px rgb(32,32,32) dotted;

* Color expansion

        #1                       #111
        #e0                      #e0e0e0
        #fc0                     #fc0

#### Important

    c#3!+bdrs2!              color: #333 !important;
                             border-radius: 2px !important;

* If you want further information, see [Emmet's documentation](http://docs.emmet.io/css-abbreviations/).

## Actions

### Go to Edit Point

Traverse between important code points in HTML.

- `<C-M-left>` is "Previous Edit Point" (`M-x emmet-prev-edit-point`)
- `<C-M-right>` is "Next Edit Point" (`M-x emmet-next-edit-point`)

For further information and demo see [Emmet's documentation](http://docs.emmet.io/actions/go-to-edit-point/).


# Why a fork? #

This for was initially inspired by the fact that `emmet-mode` uses the `cl` library, which is deprecated as of Emacs 27.1. Moreover, the repository saw its last commit in June 2018, almost three years ago at the time of writing, issues on Github seem to go unanswered and @smihica [has mentioned](https://github.com/smihica/emmet-mode/issues/99) that they themself do not use the package anymore.

This fork is currently for personal use. I cannot foresee right now if and how long I will be maintaining it in the future.

Currently, the main changes to the code are the following:

- Remove the dependency on `cl` and replace it with `cl-lib`.
- Use `emmet.el` (formerly `emmet-mode.el`) as the source file rather than generating it from the files in `src/`.
- Parse `preferences.json` and `snippets.json` in Elisp using Emacs 27's native JSON support or, if that is unavailable, `json.el`.
