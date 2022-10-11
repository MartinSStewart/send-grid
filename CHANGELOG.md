# 1.1.0

- Fix https://github.com/MartinSStewart/send-grid/issues/1
- Add `sendEmailTask`

# 2.0.0

- I forgot what changes I made here

# 3.0.0

- Replace zwilias/elm-html-string with html functions that are only defined for features that all major email clients support
- Add support for attaching files and inlining image files

# 3.0.1

- Replace missing tricycle/elm-email package with bellroy/elm-email

# 3.0.2

- Remove unused test dependency

# 4.0.0

- Remove bellroy/elm-email dependency
- Replace it with an EmailAddress type. EmailAddress uses the elm-email implementation but has a different name (to avoid collision with another Email type), is opaque instead of being a record, and makes the text lowercase so that == works as expected (A@a.com and a@a.com should count as the same email).

# 4.1.0

- Forgot to expose EmailAddress module

# 4.1.1

- The <td> tag was incorrectly rendered as <tr>
- Escape " and & characters in attributes and styles

# 4.1.2

- Fix void elements (i.e. <br>, <hr>, <input>) causing sibling elements to not get included in toString output