terraform {
    required_providers {
        vkcs = {
            source = "vk-cs/vkcs"
            version = "~> 0.10.0"
        }
    }
}

provider "vkcs" {
    # Your user account.
    username = "LeskinaSM22@st.ithub.ru"

    # The password of the account
    password = "400160MKnU8AVJ/"

    project_id = "259eb7c6129a46f6b01062f53d57b9f8"

    # Region name
    region = "RegionOne"

    auth_url = "https://infra.mail.ru:35357/v3/"

}