help() {
  echo
  echo "SP Starter Kit setup script"
  echo
  echo "Usage: ./setup.sh [options]"
  echo
  echo "Options:"
  echo
  echo "--help                           Output usage information"
  echo "-t, --tenantUrl <tenantUrl>      URL of the tenant to provision the SP Starter Kit to"
  echo "-p, --prefix [prefix]            Prefix to use for creating sites, eg. 'pnp_'. Default empty (no prefix)"
  echo "-c, --company [company]          Name of the company to use in the provisioned sites. Default 'Contoso'"
  echo "-w, --weatherCity [weatherCity]  Name of the city for which to display the weather in the weather web part"
  echo "--stockAPIKey [stockAPIKey]      API key for the stock API. Default empty"
  echo "--stockSymbol [stockSymbol]      Stock symbol to use to display the current stock value in the stock web part. Default 'MSFT'"
  echo "--skipSolutionDeployment         Set, to skip deploying the solution package"
  echo "--skipSiteCreation               Set, to skip creating sites"
  echo "--checkPoint [checkPoint]        Resume script from the given check point"
  echo
  echo "Example:"
  echo
  echo "  Provision the SP Starter Kit to the specified tenant, prefixing all created sites using '_pnp'"
  echo "    ./setup.sh --tenantUrl https://contoso.sharepoint.com --prefix pnp"
  echo
}

checkPoint() {
  if (( $checkPoint > 0)); then
    echo
    warning "You can resume the script from the last good state by adding --checkPoint $checkPoint"
    echo
  fi
}

isError() {
  # some error messages can have line breaks which break jq, so they need to be
  # removed before passing the string to jq
  res=$(echo "${1//\\r\\n/ }" | jq -r '.message')
  if [[ -z "$res" || "$res" = "null" ]]; then return 1; else return 0; fi
}

msg() {
  printf -- "$1"
}

sub() {
  printf -- "\033[90m$1\033[0m"
}

warningMsg() {
  printf -- "\033[33m$1\033[0m"
}

success() {
  printf -- "\033[32m$1\033[0m\n"
}

warning() {
  printf -- "\033[33m$1\033[0m\n"
}

error() {
  printf -- "\033[31m$1\033[0m\n"
}

errorMessage() {
  # some error messages can have line breaks which break jq, so they need to be
  # removed before passing the string to jq
  msg=$(echo "${1//\\r\\n/ }" | jq -r ".message")
  error "$msg"
}

# $1 string with key-value pairs
# $2 name of the property for which to retrieve value
getPropertyValue() {
  echo "$1" | grep -o "$2:\"[^\"]\\+" | cut -d"\"" -f2
}

# $1 customAction name
# $2 site URL
customActionExists() {
  customActionId=$(o365 spo customaction list --url $2 --output json | jq -r '.[] | select(.Name == "'"$1"'") | .Id')
  if [ -z "$customActionId" ]; then return 1; else return 0; fi
}

# $1 site URL
setupCommonExtensions() {
  siteUrl=$1
  sub '  - AlertNotification...'
  if $(customActionExists AlertNotification $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title AlertNotification --name AlertNotification --location ClientSideExtension.ApplicationCustomizer --clientSideComponentId aa8dd198-e2ee-45c5-b746-821d001bb0e1
    success 'DONE'
  fi
  sub '  - Redirect...'
  if $(customActionExists Redirect $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title Redirect --name Redirect --location ClientSideExtension.ApplicationCustomizer --clientSideComponentId f5771a9e-283e-4525-a599-554e8b9e48c2
    success 'DONE'
  fi
  sub '  - SiteClassification...'
  if $(customActionExists SiteClassification $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title SiteClassification --name SiteClassification --location ClientSideExtension.ApplicationCustomizer --clientSideComponentId 7f69d5cb-5aeb-4bc6-9f77-146aebfd9a8e --sequence 1
    success 'DONE'
  fi
}

# $1 site URL
setupCollabExtensions() {
  siteUrl=$1
  sub '- Configuring extensions...\n'
  setupCommonExtensions $siteUrl
  sub '  - DiscussNow...'
  if $(customActionExists DiscussNow $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title DiscussNow --name DiscussNow --location ClientSideExtension.ListViewCommandSet --registrationId 101 --registrationType List --clientSideComponentId 130b279d-a5d1-41b9-9fd1-4a274169b117
    success 'DONE'
  fi
  sub '  - CollabFooter...'
  if $(customActionExists CollabFooter $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title CollabFooter --name CollabFooter --location ClientSideExtension.ApplicationCustomizer --clientSideComponentId c0ab3b94-8609-40cf-861e-2a1759170b43 --clientSideComponentProperties '`{"sourceTermSet":"PnP-CollabFooter-SharedLinks","personalItemsStorageProperty":"PnP-CollabFooter-MyLinks"}`'
    success 'DONE'
  fi
}

# $1 site URL
setupPortalExtensions() {
  siteUrl=$1
  sub '- Configuring extensions...\n'
  setupCommonExtensions $siteUrl
  sub '  - PortalFooter...'
  if $(customActionExists PortalFooter $siteUrl); then
    warning 'EXISTS'
  else
    o365 spo customaction add --url $siteUrl --title PortalFooter --name PortalFooter --location ClientSideExtension.ApplicationCustomizer --clientSideComponentId b8eb4ec9-934a-4248-a15f-863d27f94f60 --clientSideComponentProperties '`{"linksListTitle":"PnP-PortalFooter-Links","copyright":"Ⓒ Copyright Contoso, 2018","support":"support@contoso.com","personalItemsStorageProperty":"PnP-CollabFooter-MyLinks"}`'
    success 'DONE'
  fi
}

# $1 site URL
# $2 list title
# $3 item title
# ... other args to pass as-is
addOrUpdateListItem() {
  # get the ID of the first item matching the title
  sub "      - $3..."
  itemId=$(o365 spo listitem list --webUrl $1 --title "$2" --filter "Title eq '$3'" --output json | jq '.[0] | .Id')
  if [ $itemId = 'null' ]; then
    sub 'CREATING...'
    o365 spo listitem add --webUrl $1 --listTitle "$2" --Title "$3" "${@:4}" >/dev/null
    success 'DONE'
  else
    sub 'UPDATING...'
    o365 spo listitem set --webUrl $1 --listTitle "$2" --id $itemId "${@:4}" >/dev/null
    success 'DONE'
  fi
}