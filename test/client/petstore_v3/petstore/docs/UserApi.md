# UserApi

All URIs are relative to */v3*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createUser**](UserApi.md#createUser) | **POST** /user | Create user
[**createUsersWithArrayInput**](UserApi.md#createUsersWithArrayInput) | **POST** /user/createWithArray | Creates list of users with given input array
[**createUsersWithListInput**](UserApi.md#createUsersWithListInput) | **POST** /user/createWithList | Creates list of users with given input array
[**deleteUser**](UserApi.md#deleteUser) | **DELETE** /user/{username} | Delete user
[**getUserByName**](UserApi.md#getUserByName) | **GET** /user/{username} | Get user by user name
[**loginUser**](UserApi.md#loginUser) | **GET** /user/login | Logs user into the system
[**logoutUser**](UserApi.md#logoutUser) | **GET** /user/logout | Logs out current logged in user session
[**updateUser**](UserApi.md#updateUser) | **PUT** /user/{username} | Updated user


# **createUser**
> createUser(_api::UserApi, in_User::User; _mediaType=nothing) <br/>
> createUser(_api::UserApi, response_stream::Channel, in_User::User; _mediaType=nothing)

Create user

This can only be done by the logged in user.

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_User** | [**User**](User.md)| Created user object | 

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createUsersWithArrayInput**
> createUsersWithArrayInput(_api::UserApi, in_User::Vector{User}; _mediaType=nothing) <br/>
> createUsersWithArrayInput(_api::UserApi, response_stream::Channel, in_User::Vector{User}; _mediaType=nothing)

Creates list of users with given input array

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_User** | [**Vector{User}**](User.md)| List of user object | 

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createUsersWithListInput**
> createUsersWithListInput(_api::UserApi, in_User::Vector{User}; _mediaType=nothing) <br/>
> createUsersWithListInput(_api::UserApi, response_stream::Channel, in_User::Vector{User}; _mediaType=nothing)

Creates list of users with given input array

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_User** | [**Vector{User}**](User.md)| List of user object | 

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteUser**
> deleteUser(_api::UserApi, in_username::String; _mediaType=nothing) <br/>
> deleteUser(_api::UserApi, response_stream::Channel, in_username::String; _mediaType=nothing)

Delete user

This can only be done by the logged in user.

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_username** | **String**| The name that needs to be deleted | [default to nothing]

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getUserByName**
> getUserByName(_api::UserApi, in_username::String; _mediaType=nothing) -> User  <br/>
> getUserByName(_api::UserApi, response_stream::Channel, in_username::String; _mediaType=nothing) -> User 

Get user by user name

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_username** | **String**| The name that needs to be fetched. Use user1 for testing. | [default to nothing]

### Return type

[**User**](User.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/xml, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **loginUser**
> loginUser(_api::UserApi, in_username::String, in_password::String; _mediaType=nothing) -> String  <br/>
> loginUser(_api::UserApi, response_stream::Channel, in_username::String, in_password::String; _mediaType=nothing) -> String 

Logs user into the system

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_username** | **String**| The user name for login | [default to nothing]
**in_password** | **String**| The password for login in clear text | [default to nothing]

### Return type

**String**

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/xml, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **logoutUser**
> logoutUser(_api::UserApi; _mediaType=nothing) <br/>
> logoutUser(_api::UserApi, response_stream::Channel; _mediaType=nothing)

Logs out current logged in user session

### Required Parameters
This endpoint does not need any parameter.

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateUser**
> updateUser(_api::UserApi, in_username::String, in_User::User; _mediaType=nothing) <br/>
> updateUser(_api::UserApi, response_stream::Channel, in_username::String, in_User::User; _mediaType=nothing)

Updated user

This can only be done by the logged in user.

### Required Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **_api** | **UserApi** | API context | 
**in_username** | **String**| name that need to be deleted | [default to nothing]
**in_User** | [**User**](User.md)| Updated user object | 

### Return type

 nothing

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

