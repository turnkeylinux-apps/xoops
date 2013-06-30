XOOPS - Content Management and Web Application Platform
=======================================================

`XOOPS`_ ("eXtensible Object Oriented Portal System") is an
award-winning object oriented PHP web application platform for
developing small or large community websites, intra company and
corporate portals, weblogs and much more. It emphasizes modularity,
advanced access control, personalization and international language
support.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- XOOPS configurations:
   
   - Installed from upstream source code to /var/www/xoops

- SSL support out of the box.
- `PHPMyAdmin`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL, phpMyAdmin: username **root**
-  XOOPS: username **admin**


.. _XOOPS: http://xoops.org/
.. _TurnKey Core: http://www.turnkeylinux.org/core
.. _PHPMyAdmin: http://www.phpmyadmin.net
