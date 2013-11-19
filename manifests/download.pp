/*

== Definition: archive::download

Archive downloader with integrity verification.

Parameters:

- *$url:
- *$digest_url:
- *$digest_string: Default value ""
- *$digest_type: Default value "md5".
- *$timeout: Default value 120.
- *$src_target: Default value "/usr/src".
- *$allow_insecure: Default value false.
- *$follow_redirects: Default value false.

Example usage:

  archive::download {"apache-tomcat-6.0.26.tar.gz":
    ensure => present,
    url    => "http://archive.apache.org/dist/tomcat/tomcat-6/v6.0.26/bin/apache-tomcat-6.0.26.tar.gz",
  }

  archive::download {"apache-tomcat-6.0.26.tar.gz":
    ensure        => present,
    digest_string => "f9eafa9bfd620324d1270ae8f09a8c89",
    url           => "http://archive.apache.org/dist/tomcat/tomcat-6/v6.0.26/bin/apache-tomcat-6.0.26.tar.gz",
  }

*/
define archive::download (
  $url,
  $ensure=present,
  $checksum=true,
  $digest_url='',
  $digest_string='',
  $digest_type='md5',
  $timeout=120,
  $src_target='/usr/src',
  $allow_insecure=false,
  $follow_redirects=false,
) {

  $insecure_arg = $allow_insecure ? {
    true    => '-k',
    default => '',
  }

  $redirect_arg = $follow_redirects ? {
    true    => '-L',
    default => '',
  }

  if ($url =~ /^http/) and !defined(Package['curl']) {
    package{'curl':
      ensure => present,
    }
  }

  case $checksum {
    true : {
      case $digest_type {
        'md5','sha1','sha224','sha256','sha384','sha512' : {
          $checksum_cmd = "${digest_type}sum -c ${name}.${digest_type}"
        }
        default: { fail 'Unimplemented digest type' }
      }

      # digest_string is prior to digest_url
      if $digest_string == '' {

        if $url =~ /^puppet/ { fail "No digest string" }

        case $ensure {
          present: {

            if $digest_url == '' {
              $digest_src = "${url}.${digest_type}"
            } else {
              $digest_src = $digest_url
            }

            exec { "download digest of archive $name":
              command => "curl ${insecure_arg} ${redirect_arg} -o ${src_target}/${name}.${digest_type} ${digest_src}",
              creates => "${src_target}/${name}.${digest_type}",
              path    => "/bin:/usr/bin",
              timeout => $timeout,
              notify  => Exec["download archive $name by curl and check sum"],
              require => Package['curl'],
            }

          }
          absent: {
            file{"${src_target}/${name}.${digest_type}":
              ensure => absent,
              purge  => true,
              force  => true,
            }
          }
        }
      }

      if $digest_string != '' {
        case $ensure {
          present: {
            if $url =~ /^puppet/ {
              file { "${src_target}/${name}.${digest_type}":
                ensure  => $ensure,
                content => "${digest_string} *${name}",
              }
            } else {
              file { "${src_target}/${name}.${digest_type}":
                ensure  => $ensure,
                content => "${digest_string} *${name}",
                notify  => Exec["download archive $name by curl and check sum"],
              }
            }
          }
          absent: {
            file {"${src_target}/${name}.${digest_type}":
              ensure => absent,
              purge  => true,
              force  => true,
            }
          }
        }
      }
    }
    false :  { notice 'No checksum for this archive' }
    default: { fail ( "Unknown checksum value: '${checksum}'" ) }
  }

  case $ensure {
    present: {
      case $url {
        /^puppet/: {
          file { "download archive $name by puppet and check sum":
            ensure    => present,
            path      => "${src_target}/${name}",
            source    => $url,
            notify    => $checksum ? {
              true    => Exec["rm-on-error-${name}"],
              default => undef,
            },
            require   => $checksum ? {
              true    => File["${src_target}/${name}.${digest_type}"],
              default => undef,
            },
          }
        }
        /^http/: {
          exec {"download archive $name by curl and check sum":
            command   => "curl ${insecure_arg} ${redirect_arg} -o ${src_target}/${name} ${url}",
            creates   => "${src_target}/${name}",
            path      => "/bin:/usr/bin",
            logoutput => true,
            timeout   => $timeout,
            require   => Package['curl'],
            notify    => $checksum ? {
              true    => Exec["rm-on-error-${name}"],
              default => undef,
            },
            refreshonly => $checksum ? {
              true      => true,
              default   => undef,
            },
          }
        }
        default: { fail "Download error. Protocol not supported" }
      }

      exec {"rm-on-error-${name}":
        command     => "rm -f ${src_target}/${name} ${src_target}/${name}.${digest_type} && exit 1",
        unless      => $checksum_cmd,
        path        => "/bin:/usr/bin",
        cwd         => $src_target,
        refreshonly => true,
      }
    }
    absent: {
      file {"${src_target}/${name}":
        ensure => absent,
        purge  => true,
        force  => true,
      }
    }
    default: { fail ( "Unknown ensure value: '${ensure}'" ) }
  }
}
